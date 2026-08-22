//! End-to-end check of the MPRIS D-Bus layer against a *real* session bus.
//!
//! A minimal conforming player is published on the bus and then discovered and
//! driven through `DbusMediaPlayerHost` exactly as a phone's request would.
//! This is what distinguishes "the packet serialized" from "the media control
//! actually works": discovery, property reads, unit conversion and method
//! dispatch all run against real D-Bus here.
//!
//! Skips (rather than fails) where no session bus exists, so CI containers and
//! headless builds stay green.

#![cfg(all(target_os = "linux", feature = "mpris"))]

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use relay_core::kdeconnect::media::{dbus::DbusMediaPlayerHost, MediaPlayerHost, PlayerCommand};
use zbus::zvariant::{ObjectPath, OwnedValue, Value};
use zbus::{connection, interface};

const TEST_BUS_NAME: &str = "org.mpris.MediaPlayer2.relayintegrationtest";

#[derive(Clone, Default)]
struct Calls(Arc<Mutex<Vec<String>>>);

struct RootIface;

#[interface(name = "org.mpris.MediaPlayer2")]
impl RootIface {
    #[zbus(property)]
    fn identity(&self) -> String {
        "Relay Integration Test Player".to_owned()
    }
}

struct PlayerIface {
    calls: Calls,
    volume: Mutex<f64>,
}

#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl PlayerIface {
    fn play(&self) {
        self.calls.0.lock().unwrap().push("Play".into());
    }
    fn pause(&self) {
        self.calls.0.lock().unwrap().push("Pause".into());
    }
    #[zbus(name = "PlayPause")]
    fn play_pause(&self) {
        self.calls.0.lock().unwrap().push("PlayPause".into());
    }
    fn stop(&self) {
        self.calls.0.lock().unwrap().push("Stop".into());
    }
    fn next(&self) {
        self.calls.0.lock().unwrap().push("Next".into());
    }
    fn previous(&self) {
        self.calls.0.lock().unwrap().push("Previous".into());
    }
    fn seek(&self, offset: i64) {
        self.calls.0.lock().unwrap().push(format!("Seek({offset})"));
    }
    #[zbus(name = "SetPosition")]
    fn set_position(&self, _track: ObjectPath<'_>, position: i64) {
        self.calls
            .0
            .lock()
            .unwrap()
            .push(format!("SetPosition({position})"));
    }

    #[zbus(property)]
    fn playback_status(&self) -> String {
        "Playing".to_owned()
    }
    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let mut metadata = HashMap::new();
        metadata.insert(
            "mpris:trackid".to_owned(),
            OwnedValue::try_from(Value::from(
                ObjectPath::try_from("/org/relay/track/1").unwrap(),
            ))
            .unwrap(),
        );
        // 210 seconds, in MPRIS's microseconds.
        metadata.insert(
            "mpris:length".to_owned(),
            OwnedValue::try_from(Value::from(210_000_000_i64)).unwrap(),
        );
        metadata.insert(
            "xesam:title".to_owned(),
            OwnedValue::try_from(Value::from("Integration Title")).unwrap(),
        );
        metadata.insert(
            "xesam:artist".to_owned(),
            OwnedValue::try_from(Value::from(vec!["Integration Artist".to_owned()])).unwrap(),
        );
        metadata.insert(
            "xesam:album".to_owned(),
            OwnedValue::try_from(Value::from("Integration Album")).unwrap(),
        );
        metadata.insert(
            "mpris:artUrl".to_owned(),
            OwnedValue::try_from(Value::from("file:///tmp/relay-art.png")).unwrap(),
        );
        metadata
    }
    #[zbus(property)]
    fn volume(&self) -> f64 {
        *self.volume.lock().unwrap()
    }
    #[zbus(property)]
    fn set_volume(&self, value: f64) {
        *self.volume.lock().unwrap() = value;
        self.calls.0.lock().unwrap().push(format!("Volume={value}"));
    }
    #[zbus(property)]
    fn position(&self) -> i64 {
        1_500_000
    }
    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }
    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        false
    }
    #[zbus(property)]
    fn can_seek(&self) -> bool {
        true
    }
}

/// Publishes the test player, or returns `None` when there is no session bus.
async fn serve(calls: Calls) -> Option<zbus::Connection> {
    connection::Builder::session()
        .ok()?
        .name(TEST_BUS_NAME)
        .ok()?
        .serve_at("/org/mpris/MediaPlayer2", RootIface)
        .ok()?
        .serve_at(
            "/org/mpris/MediaPlayer2",
            PlayerIface {
                calls,
                volume: Mutex::new(0.42),
            },
        )
        .ok()?
        .build()
        .await
        .ok()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn a_real_mpris_player_is_discovered_read_and_controlled_over_dbus() {
    let calls = Calls::default();
    let Some(_served) = serve(calls.clone()).await else {
        eprintln!("skipping: no D-Bus session bus available");
        return;
    };
    let Ok(host) = DbusMediaPlayerHost::connect().await else {
        eprintln!("skipping: could not connect to the session bus");
        return;
    };

    // --- discovery, by bus-name prefix alone: no application is special-cased.
    let players = host.players().await;
    let found = players
        .iter()
        .find(|player| player.name == "Relay Integration Test Player")
        .expect("the served player must be discovered");

    // --- metadata and unit conversion, as the phone will receive them.
    assert_eq!(found.title.as_deref(), Some("Integration Title"));
    assert_eq!(found.artist.as_deref(), Some("Integration Artist"));
    assert_eq!(found.album.as_deref(), Some("Integration Album"));
    assert_eq!(found.album_art_url.as_deref(), Some("file:///tmp/relay-art.png"));
    assert!(found.is_playing);
    // Microseconds on the bus become the milliseconds KDE Connect speaks.
    assert_eq!(found.length_ms, Some(210_000));
    assert_eq!(found.position_ms, Some(1_500));
    // 0.0-1.0 on the bus becomes 0-100 in the packet.
    assert_eq!(found.volume, Some(42));
    assert!(found.can_play && found.can_pause && found.can_go_next && found.can_seek);
    assert!(!found.can_go_previous, "capability flags are read, not assumed");

    // --- the packet the phone actually receives.
    let packet = found.to_body().to_packet();
    assert_eq!(packet.packet_type, "kdeconnect.mpris");
    assert_eq!(
        packet.body.get("title").and_then(serde_json::Value::as_str),
        Some("Integration Title")
    );
    assert_eq!(
        packet.body.get("canGoPrevious").and_then(serde_json::Value::as_bool),
        Some(false)
    );

    // --- control: every transport action reaches the real player.
    let name = found.name.clone();
    for (command, expected) in [
        (PlayerCommand::Play, "Play"),
        (PlayerCommand::Pause, "Pause"),
        (PlayerCommand::PlayPause, "PlayPause"),
        (PlayerCommand::Stop, "Stop"),
        (PlayerCommand::Next, "Next"),
        (PlayerCommand::Previous, "Previous"),
    ] {
        host.control(&name, command).await.expect("control must reach the player");
        assert_eq!(
            calls.0.lock().unwrap().last().map(String::as_str),
            Some(expected)
        );
    }

    // Seek passes microseconds straight through.
    host.control(&name, PlayerCommand::SeekUs(-5_000_000)).await.unwrap();
    assert_eq!(
        calls.0.lock().unwrap().last().map(String::as_str),
        Some("Seek(-5000000)")
    );

    // SetPosition is addressed to the current track and converted to microseconds.
    host.control(&name, PlayerCommand::SetPositionMs(30_000)).await.unwrap();
    assert_eq!(
        calls.0.lock().unwrap().last().map(String::as_str),
        Some("SetPosition(30000000)")
    );

    // Volume is written back on the MPRIS 0.0-1.0 scale.
    host.control(&name, PlayerCommand::SetVolume(80)).await.unwrap();
    assert!(
        calls.0.lock().unwrap().iter().any(|call| call.starts_with("Volume=0.8")),
        "volume must be written on the bus scale, got {:?}",
        calls.0.lock().unwrap()
    );

    // --- an unknown player is refused, never resolved to a different one.
    assert!(host.player("A Player That Does Not Exist").await.is_none());
    let before = calls.0.lock().unwrap().len();
    assert!(host
        .control("A Player That Does Not Exist", PlayerCommand::Play)
        .await
        .is_err());
    assert_eq!(
        calls.0.lock().unwrap().len(),
        before,
        "an unknown player must not fall through to the real one"
    );
}
