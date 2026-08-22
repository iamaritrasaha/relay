//! Remote input via the XDG Desktop Portal `RemoteDesktop` interface.
//!
//! This is the supported way to inject input on GNOME Wayland. XTest is X11-only
//! and does nothing under Wayland, and writing to `/dev/uinput` needs privileges
//! Relay must not hold -- so the portal is not merely one option among several,
//! it is the one path that both works and stays inside the sandbox rules.
//!
//! # Authorisation
//!
//! A session is *not* created at startup. `CreateSession` -> `SelectDevices` ->
//! `Start` is run only when the desktop user asks for it, and `Start` is what
//! raises GNOME's own approval dialog. Until the user approves, [`is_ready`]
//! reports false and every inbound input packet is refused. Being paired -- over
//! LAN or WAN -- is therefore never sufficient on its own to move the cursor.
//!
//! [`is_ready`]: PortalRemoteInputBackend::is_ready

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::{Context as _, Result};
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value as ZValue};
use zbus::{Connection, Proxy};

use super::{InputEvent, InputFuture, RemoteInputBackend};

const PORTAL_BUS: &str = "org.freedesktop.portal.Desktop";
const PORTAL_PATH: &str = "/org/freedesktop/portal/desktop";
const IFACE_REMOTE_DESKTOP: &str = "org.freedesktop.portal.RemoteDesktop";

/// `SelectDevices` bitmask: keyboard | pointer. Touchscreen is deliberately not
/// requested -- Relay's remote input is a trackpad and keyboard, and asking for
/// capabilities the feature never uses would overstate what the user is
/// approving.
const DEVICE_KEYBOARD: u32 = 1;
const DEVICE_POINTER: u32 = 2;

/// Portal-backed input injection.
pub struct PortalRemoteInputBackend {
    connection: Connection,
    session: OwnedObjectPath,
    ready: AtomicBool,
}

impl PortalRemoteInputBackend {
    /// Runs the full portal handshake, including the user's approval dialog.
    ///
    /// Returns an error rather than a half-usable backend when the portal is
    /// missing or the user declines, so the caller can report honestly that
    /// remote input is unavailable instead of silently dropping every event.
    pub async fn start() -> Result<Self> {
        let connection = Connection::session()
            .await
            .context("connect to the session bus for the RemoteDesktop portal")?;
        let proxy = Proxy::new(&connection, PORTAL_BUS, PORTAL_PATH, IFACE_REMOTE_DESKTOP)
            .await
            .context("open the RemoteDesktop portal; is xdg-desktop-portal running?")?;

        let token = request_token();
        let session_token = format!("relay_session_{}", uuid::Uuid::new_v4().simple());
        let mut options: HashMap<&str, ZValue<'_>> = HashMap::new();
        options.insert("handle_token", ZValue::from(token.as_str()));
        options.insert("session_handle_token", ZValue::from(session_token.as_str()));
        let create: OwnedObjectPath = proxy.call("CreateSession", &(options,)).await?;
        let session = await_session_handle(&connection, &create).await?;

        let token = request_token();
        let mut options: HashMap<&str, ZValue<'_>> = HashMap::new();
        options.insert("handle_token", ZValue::from(token.as_str()));
        options.insert("types", ZValue::from(DEVICE_KEYBOARD | DEVICE_POINTER));
        let select: OwnedObjectPath = proxy
            .call("SelectDevices", &(&session, options))
            .await
            .context("select remote-input device types")?;
        await_response(&connection, &select).await?;

        // `Start` is the call that asks the user. Anything short of approval
        // shows up as a non-zero response and is treated as "no session".
        let token = request_token();
        let mut options: HashMap<&str, ZValue<'_>> = HashMap::new();
        options.insert("handle_token", ZValue::from(token.as_str()));
        let start: OwnedObjectPath = proxy
            .call("Start", &(&session, "", options))
            .await
            .context("start the remote-input session")?;
        await_response(&connection, &start)
            .await
            .context("remote input was not authorised")?;

        Ok(Self {
            connection,
            session,
            ready: AtomicBool::new(true),
        })
    }

    async fn proxy(&self) -> Result<Proxy<'_>> {
        Proxy::new(&self.connection, PORTAL_BUS, PORTAL_PATH, IFACE_REMOTE_DESKTOP)
            .await
            .map_err(Into::into)
    }

    /// Marks the session unusable after a failed call, so later packets are
    /// refused cleanly instead of erroring one at a time forever.
    fn invalidate(&self, error: &anyhow::Error) {
        if self.ready.swap(false, Ordering::SeqCst) {
            tracing::warn!("[Relay Input] remote-input session ended: {error}");
        }
    }

    async fn apply(&self, proxy: &Proxy<'_>, event: &InputEvent) -> Result<()> {
        let empty: HashMap<&str, ZValue<'_>> = HashMap::new();
        let session: &ObjectPath<'_> = &self.session;
        match event {
            InputEvent::PointerMotion { dx, dy } => {
                proxy
                    .call::<_, _, ()>("NotifyPointerMotion", &(session, &empty, *dx, *dy))
                    .await?
            }
            InputEvent::PointerButton { button, pressed } => {
                proxy
                    .call::<_, _, ()>(
                        "NotifyPointerButton",
                        &(session, &empty, button.evdev_code(), u32::from(*pressed)),
                    )
                    .await?
            }
            InputEvent::Scroll { dx, dy } => {
                proxy
                    .call::<_, _, ()>("NotifyPointerAxis", &(session, &empty, *dx, *dy))
                    .await?
            }
            InputEvent::Keysym { keysym, pressed } => {
                proxy
                    .call::<_, _, ()>(
                        "NotifyKeyboardKeysym",
                        &(session, &empty, *keysym, u32::from(*pressed)),
                    )
                    .await?
            }
            InputEvent::Text(text) => {
                for character in text.chars() {
                    let keysym = keysym_for_char(character);
                    proxy
                        .call::<_, _, ()>("NotifyKeyboardKeysym", &(session, &empty, keysym, 1_u32))
                        .await?;
                    proxy
                        .call::<_, _, ()>("NotifyKeyboardKeysym", &(session, &empty, keysym, 0_u32))
                        .await?;
                }
            }
        }
        Ok(())
    }
}

impl RemoteInputBackend for PortalRemoteInputBackend {
    fn is_ready(&self) -> bool {
        self.ready.load(Ordering::SeqCst)
    }

    fn dispatch<'a>(&'a self, events: &'a [InputEvent]) -> InputFuture<'a, Result<()>> {
        Box::pin(async move {
            if !self.is_ready() {
                anyhow::bail!("no authorised remote-input session");
            }
            let proxy = self.proxy().await?;
            for event in events {
                if let Err(error) = self.apply(&proxy, event).await {
                    self.invalidate(&error);
                    return Err(error);
                }
            }
            Ok(())
        })
    }
}

/// X11 keysym for a character.
///
/// Latin-1 maps directly onto its codepoint; everything else uses the Unicode
/// keysym range, which is the standard X11 rule and what compositors decode.
fn keysym_for_char(character: char) -> i32 {
    let codepoint = character as u32;
    if codepoint < 0x100 {
        codepoint as i32
    } else {
        (0x0100_0000 + codepoint) as i32
    }
}

/// Portal request handles must be unique per call and are echoed back on the
/// response object path.
fn request_token() -> String {
    format!("relay_{}", uuid::Uuid::new_v4().simple())
}

/// Waits for a portal `Request::Response` signal and returns its results.
///
/// The portal answers asynchronously on a per-request object, so a call is only
/// complete once this signal arrives -- returning early would race the user's
/// approval dialog.
async fn await_results(
    connection: &Connection,
    request: &OwnedObjectPath,
) -> Result<(u32, HashMap<String, OwnedValue>)> {
    use futures_util::StreamExt as _;
    let proxy = Proxy::new(
        connection,
        PORTAL_BUS,
        request.as_str(),
        "org.freedesktop.portal.Request",
    )
    .await?;
    let mut stream = proxy.receive_signal("Response").await?;
    let message = stream.next().await.context("portal closed without responding")?;
    let (response, results): (u32, HashMap<String, OwnedValue>) = message.body().deserialize()?;
    Ok((response, results))
}

async fn await_response(connection: &Connection, request: &OwnedObjectPath) -> Result<()> {
    let (response, _) = await_results(connection, request).await?;
    // 0 = success, 1 = user cancelled, 2 = ended some other way.
    if response != 0 {
        anyhow::bail!("portal request was not granted (response {response})");
    }
    Ok(())
}

async fn await_session_handle(
    connection: &Connection,
    request: &OwnedObjectPath,
) -> Result<OwnedObjectPath> {
    let (response, results) = await_results(connection, request).await?;
    if response != 0 {
        anyhow::bail!("portal did not create a session (response {response})");
    }
    let handle = results
        .get("session_handle")
        .context("portal response carried no session_handle")?;
    // Portal versions differ on whether this is an 'o' or an 's'.
    if let Ok(path) = OwnedObjectPath::try_from(handle.clone()) {
        return Ok(path);
    }
    let text = String::try_from(handle.clone()).context("unreadable session_handle")?;
    Ok(OwnedObjectPath::from(ObjectPath::try_from(text)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn latin1_characters_use_their_codepoint_as_keysym() {
        assert_eq!(keysym_for_char('a'), 0x61);
        assert_eq!(keysym_for_char('Z'), 0x5a);
        assert_eq!(keysym_for_char(' '), 0x20);
        assert_eq!(keysym_for_char('~'), 0x7e);
    }

    #[test]
    fn characters_beyond_latin1_use_the_unicode_keysym_range() {
        // The 0x01000000 offset is what compositors decode back to Unicode.
        assert_eq!(keysym_for_char('€'), 0x0100_20ac);
        assert_eq!(keysym_for_char('日'), 0x0100_65e5);
    }

    #[test]
    fn request_tokens_are_unique_and_dbus_safe() {
        let a = request_token();
        let b = request_token();
        assert_ne!(a, b);
        // Portal tokens become part of an object path, so they may only contain
        // path-safe characters.
        assert!(a.chars().all(|c| c.is_ascii_alphanumeric() || c == '_'), "{a}");
    }

    #[test]
    fn only_keyboard_and_pointer_are_requested() {
        // Touchscreen (4) is intentionally excluded: the user should not be
        // asked to approve a capability the feature never uses.
        assert_eq!(DEVICE_KEYBOARD | DEVICE_POINTER, 3);
    }
}
