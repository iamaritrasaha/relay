//! Generic MPRIS-over-D-Bus implementation of [`MediaPlayerHost`].
//!
//! Discovery is by bus-name prefix (`org.mpris.MediaPlayer2.*`) and every read
//! and write goes through the two standard interfaces, so any conforming player
//! works with no per-application knowledge: nothing here names Spotify, VLC,
//! Firefox or anything else, and `playerctl` is not involved.
//!
//! Everything runs on the tokio runtime Relay already has (zbus is built with
//! its `tokio` feature), so a slow or hung player blocks only the task serving
//! that one request.

use std::collections::HashMap;

use anyhow::{Context as _, Result};
use zbus::zvariant::{ObjectPath, OwnedValue};
use zbus::{Connection, Proxy};

use super::{HostFuture, MediaPlayerHost, PlayerCommand, PlayerSnapshot};

const MPRIS_BUS_PREFIX: &str = "org.mpris.MediaPlayer2.";
const MPRIS_OBJECT_PATH: &str = "/org/mpris/MediaPlayer2";
const IFACE_ROOT: &str = "org.mpris.MediaPlayer2";
const IFACE_PLAYER: &str = "org.mpris.MediaPlayer2.Player";

/// Live session-bus view of the machine's MPRIS players.
pub struct DbusMediaPlayerHost {
    connection: Connection,
}

impl DbusMediaPlayerHost {
    /// Connects to the session bus. Fails (rather than degrading silently) when
    /// there is no session bus at all -- a headless service, say -- so the
    /// caller can decide to run without media support.
    pub async fn connect() -> Result<Self> {
        let connection = Connection::session()
            .await
            .context("connect to the D-Bus session bus for MPRIS")?;
        Ok(Self { connection })
    }

    /// Every `org.mpris.MediaPlayer2.*` name currently owned on the bus.
    async fn player_bus_names(&self) -> Result<Vec<String>> {
        let proxy = Proxy::new(
            &self.connection,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
        )
        .await?;
        let names: Vec<String> = proxy.call("ListNames", &()).await?;
        let mut players: Vec<String> = names
            .into_iter()
            .filter(|name| name.starts_with(MPRIS_BUS_PREFIX))
            .collect();
        // Stable order so the player list the phone sees does not reshuffle
        // between refreshes.
        players.sort();
        Ok(players)
    }

    async fn proxy(&self, bus_name: &str, interface: &'static str) -> Result<Proxy<'_>> {
        Proxy::new(&self.connection, bus_name.to_owned(), MPRIS_OBJECT_PATH, interface)
            .await
            .with_context(|| format!("open {interface} proxy"))
    }

    /// Reads one player into a snapshot. Individual properties are optional
    /// throughout: real players omit plenty of them, and a missing `Shuffle` must
    /// not cost us the title.
    async fn snapshot(&self, bus_name: &str) -> Result<PlayerSnapshot> {
        let root = self.proxy(bus_name, IFACE_ROOT).await?;
        let player = self.proxy(bus_name, IFACE_PLAYER).await?;

        // `Identity` is the human name the phone shows and addresses. Falling
        // back to the bus suffix keeps a non-conforming player usable.
        let name: String = root
            .get_property("Identity")
            .await
            .ok()
            .unwrap_or_else(|| bus_name.trim_start_matches(MPRIS_BUS_PREFIX).to_owned());

        let metadata: HashMap<String, OwnedValue> =
            player.get_property("Metadata").await.unwrap_or_default();

        let playback_status: String = player
            .get_property("PlaybackStatus")
            .await
            .unwrap_or_else(|_| "Stopped".to_owned());

        let volume: Option<f64> = player.get_property("Volume").await.ok();
        let position_us: Option<i64> = player.get_property("Position").await.ok();

        Ok(PlayerSnapshot {
            name,
            title: metadata_string(&metadata, "xesam:title"),
            artist: metadata_first_of_list(&metadata, "xesam:artist"),
            album: metadata_string(&metadata, "xesam:album"),
            url: metadata_string(&metadata, "xesam:url"),
            album_art_url: metadata_string(&metadata, "mpris:artUrl"),
            loop_status: player.get_property::<String>("LoopStatus").await.ok(),
            shuffle: player.get_property::<bool>("Shuffle").await.ok(),
            volume: volume.map(volume_to_percent),
            length_ms: metadata_i64(&metadata, "mpris:length").map(us_to_ms),
            position_ms: position_us.map(us_to_ms),
            is_playing: playback_status == "Playing",
            can_play: player.get_property("CanPlay").await.unwrap_or(false),
            can_pause: player.get_property("CanPause").await.unwrap_or(false),
            can_go_next: player.get_property("CanGoNext").await.unwrap_or(false),
            can_go_previous: player.get_property("CanGoPrevious").await.unwrap_or(false),
            can_seek: player.get_property("CanSeek").await.unwrap_or(false),
        })
    }

    /// Resolves the phone-facing player name back to a bus name.
    ///
    /// Matching is by `Identity` first and bus suffix second, so a phone that
    /// cached either form still lands on the right player. Returns `None` for a
    /// name that no longer exists rather than falling through to some other
    /// player.
    async fn bus_name_for(&self, name: &str) -> Result<Option<String>> {
        for bus_name in self.player_bus_names().await? {
            if bus_name.trim_start_matches(MPRIS_BUS_PREFIX) == name {
                return Ok(Some(bus_name));
            }
            if let Ok(root) = self.proxy(&bus_name, IFACE_ROOT).await {
                if root.get_property::<String>("Identity").await.as_deref() == Ok(name) {
                    return Ok(Some(bus_name));
                }
            }
        }
        Ok(None)
    }

    /// Watches the bus for anything that could change what a phone should see:
    /// a player's properties changing, and players appearing or disappearing.
    ///
    /// Emits a bare tick rather than the changed values. Ticks are coalesced by
    /// the receiver, so a burst (a track change updates Metadata, PlaybackStatus
    /// and Position within milliseconds) costs one refresh, not three.
    async fn spawn_change_watcher(&self) -> Result<tokio::sync::mpsc::Receiver<()>> {
        use futures_util::StreamExt as _;
        use zbus::MatchRule;

        let properties = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.DBus.Properties")?
            .member("PropertiesChanged")?
            .path(MPRIS_OBJECT_PATH)?
            .build();
        // zbus 5's builder has no `arg0namespace`, so the rule matches every
        // name change and non-MPRIS ones are discarded below rather than
        // triggering a pointless bus re-scan.
        let names = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.DBus")?
            .member("NameOwnerChanged")?
            .build();

        let mut property_stream =
            zbus::MessageStream::for_match_rule(properties, &self.connection, Some(8)).await?;
        let mut name_stream =
            zbus::MessageStream::for_match_rule(names, &self.connection, Some(8)).await?;

        let (tx, rx) = tokio::sync::mpsc::channel(1);
        tokio::spawn(async move {
            loop {
                let changed = tokio::select! {
                    message = property_stream.next() => message.map(|_| true),
                    message = name_stream.next() => match message {
                        Some(Ok(message)) => {
                            // Only a player coming or going matters here.
                            let name: Option<String> = message.body().deserialize::<(String, String, String)>()
                                .ok()
                                .map(|(name, _, _)| name);
                            Some(name.is_some_and(|name| name.starts_with(MPRIS_BUS_PREFIX)))
                        }
                        Some(Err(_)) => Some(false),
                        None => None,
                    },
                };
                let Some(changed) = changed else {
                    break;
                };
                if !changed {
                    continue;
                }
                // A full channel already means "a refresh is pending", so
                // dropping this tick loses nothing.
                let _ = tx.try_send(());
            }
        });
        Ok(rx)
    }

    async fn apply(&self, bus_name: &str, command: PlayerCommand) -> Result<()> {
        let player = self.proxy(bus_name, IFACE_PLAYER).await?;
        match command {
            PlayerCommand::Play => player.call::<_, _, ()>("Play", &()).await?,
            PlayerCommand::Pause => player.call::<_, _, ()>("Pause", &()).await?,
            PlayerCommand::PlayPause => player.call::<_, _, ()>("PlayPause", &()).await?,
            PlayerCommand::Stop => player.call::<_, _, ()>("Stop", &()).await?,
            PlayerCommand::Next => player.call::<_, _, ()>("Next", &()).await?,
            PlayerCommand::Previous => player.call::<_, _, ()>("Previous", &()).await?,
            PlayerCommand::SeekUs(offset) => player.call::<_, _, ()>("Seek", &(offset,)).await?,
            PlayerCommand::SetVolume(percent) => {
                player
                    .set_property("Volume", percent_to_volume(percent))
                    .await?
            }
            PlayerCommand::SetLoopStatus(status) => {
                player.set_property("LoopStatus", status).await?
            }
            PlayerCommand::SetShuffle(shuffle) => player.set_property("Shuffle", shuffle).await?,
            PlayerCommand::SetPositionMs(position_ms) => {
                // MPRIS SetPosition is addressed to a specific track so a
                // seek cannot land on the wrong one after a track change. A
                // player that exposes no trackid gets a relative Seek instead,
                // which is the closest honest equivalent.
                let metadata: HashMap<String, OwnedValue> =
                    player.get_property("Metadata").await.unwrap_or_default();
                let track_id = metadata
                    .get("mpris:trackid")
                    .and_then(|value| ObjectPath::try_from(value.clone()).ok());
                let target_us = ms_to_us(position_ms);
                match track_id {
                    Some(track_id) => {
                        player
                            .call::<_, _, ()>("SetPosition", &(track_id, target_us))
                            .await?
                    }
                    None => {
                        let current_us: i64 = player.get_property("Position").await.unwrap_or(0);
                        player
                            .call::<_, _, ()>("Seek", &(target_us - current_us,))
                            .await?
                    }
                }
            }
        }
        Ok(())
    }
}

impl MediaPlayerHost for DbusMediaPlayerHost {
    fn players(&self) -> HostFuture<'_, Vec<PlayerSnapshot>> {
        Box::pin(async move {
            let bus_names = match self.player_bus_names().await {
                Ok(names) => names,
                Err(error) => {
                    tracing::warn!("[Relay MPRIS] listing players failed: {error}");
                    return Vec::new();
                }
            };
            let mut snapshots = Vec::with_capacity(bus_names.len());
            for bus_name in bus_names {
                // One unresponsive player must not hide every other player.
                match self.snapshot(&bus_name).await {
                    Ok(snapshot) => snapshots.push(snapshot),
                    Err(error) => {
                        tracing::debug!("[Relay MPRIS] skipping {bus_name}: {error}");
                    }
                }
            }
            snapshots
        })
    }

    fn player<'a>(&'a self, name: &'a str) -> HostFuture<'a, Option<PlayerSnapshot>> {
        Box::pin(async move {
            match self.bus_name_for(name).await {
                Ok(Some(bus_name)) => self.snapshot(&bus_name).await.ok(),
                Ok(None) => None,
                Err(error) => {
                    tracing::warn!("[Relay MPRIS] resolving a player failed: {error}");
                    None
                }
            }
        })
    }

    fn subscribe(&self) -> HostFuture<'_, Option<tokio::sync::mpsc::Receiver<()>>> {
        Box::pin(async move {
            match self.spawn_change_watcher().await {
                Ok(rx) => Some(rx),
                Err(error) => {
                    tracing::warn!("[Relay MPRIS] change notifications unavailable: {error}");
                    None
                }
            }
        })
    }

    fn control<'a>(&'a self, name: &'a str, command: PlayerCommand) -> HostFuture<'a, Result<()>> {
        Box::pin(async move {
            let bus_name = self
                .bus_name_for(name)
                .await?
                .context("no such MPRIS player")?;
            self.apply(&bus_name, command).await
        })
    }
}

// --- unit conversions and metadata extraction (pure, unit-tested below) ---

/// MPRIS counts in microseconds; KDE Connect packets count in milliseconds.
fn us_to_ms(microseconds: i64) -> i64 {
    microseconds / 1_000
}

fn ms_to_us(milliseconds: i64) -> i64 {
    milliseconds.saturating_mul(1_000)
}

/// MPRIS volume is 0.0-1.0; KDE Connect sends 0-100. Clamped because players
/// are permitted to report above 1.0 for amplification.
fn volume_to_percent(volume: f64) -> i64 {
    (volume * 100.0).round().clamp(0.0, 100.0) as i64
}

fn percent_to_volume(percent: i64) -> f64 {
    (percent.clamp(0, 100) as f64) / 100.0
}

fn metadata_string(metadata: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    let value = metadata.get(key)?;
    String::try_from(value.clone()).ok().filter(|s| !s.is_empty())
}

fn metadata_i64(metadata: &HashMap<String, OwnedValue>, key: &str) -> Option<i64> {
    let value = metadata.get(key)?;
    // Players disagree on the integer width they publish, so try the widths
    // seen in the wild rather than insisting on the specified one.
    if let Ok(v) = i64::try_from(value.clone()) {
        return Some(v);
    }
    if let Ok(v) = u64::try_from(value.clone()) {
        return i64::try_from(v).ok();
    }
    if let Ok(v) = i32::try_from(value.clone()) {
        return Some(v as i64);
    }
    if let Ok(v) = u32::try_from(value.clone()) {
        return Some(v as i64);
    }
    None
}

/// `xesam:artist` is specified as a string *array*; some players publish a bare
/// string instead. Both are accepted, and an empty array yields no artist rather
/// than an empty one.
fn metadata_first_of_list(metadata: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    let value = metadata.get(key)?;
    if let Ok(list) = Vec::<String>::try_from(value.clone()) {
        return list.into_iter().find(|item| !item.is_empty());
    }
    if let Ok(single) = String::try_from(value.clone()) {
        return Some(single).filter(|s| !s.is_empty());
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use zbus::zvariant::Value as ZValue;

    fn owned(value: ZValue<'_>) -> OwnedValue {
        OwnedValue::try_from(value).unwrap()
    }

    #[test]
    fn microseconds_convert_to_the_milliseconds_kde_connect_expects() {
        assert_eq!(us_to_ms(210_000_000), 210_000);
        assert_eq!(us_to_ms(0), 0);
        assert_eq!(ms_to_us(1_500), 1_500_000);
        // A track length no player will ever report, but the conversion must
        // not wrap into a negative position.
        assert_eq!(ms_to_us(i64::MAX), i64::MAX);
    }

    #[test]
    fn volume_round_trips_between_the_mpris_and_kde_scales() {
        assert_eq!(volume_to_percent(0.0), 0);
        assert_eq!(volume_to_percent(0.42), 42);
        assert_eq!(volume_to_percent(1.0), 100);
        // Amplifying players may exceed 1.0; KDE Connect's scale stops at 100.
        assert_eq!(volume_to_percent(1.5), 100);
        assert_eq!(volume_to_percent(-0.2), 0);

        assert!((percent_to_volume(50) - 0.5).abs() < f64::EPSILON);
        assert!((percent_to_volume(200) - 1.0).abs() < f64::EPSILON);
        assert!((percent_to_volume(-5) - 0.0).abs() < f64::EPSILON);
    }

    #[test]
    fn metadata_strings_are_read_and_empty_values_are_treated_as_absent() {
        let mut metadata = HashMap::new();
        metadata.insert("xesam:title".to_owned(), owned(ZValue::from("Song")));
        metadata.insert("xesam:album".to_owned(), owned(ZValue::from("")));

        assert_eq!(metadata_string(&metadata, "xesam:title"), Some("Song".into()));
        // An empty album must be omitted, not sent as "" -- the phone would
        // overwrite a good previous value with the blank.
        assert_eq!(metadata_string(&metadata, "xesam:album"), None);
        assert_eq!(metadata_string(&metadata, "xesam:missing"), None);
    }

    #[test]
    fn track_length_is_accepted_in_whichever_integer_width_a_player_publishes() {
        for value in [
            owned(ZValue::from(210_000_000_i64)),
            owned(ZValue::from(210_000_000_u64)),
            owned(ZValue::from(210_000_000_i32)),
            owned(ZValue::from(210_000_000_u32)),
        ] {
            let mut metadata = HashMap::new();
            metadata.insert("mpris:length".to_owned(), value);
            assert_eq!(metadata_i64(&metadata, "mpris:length"), Some(210_000_000));
        }
    }

    #[test]
    fn a_non_numeric_track_length_yields_no_length_rather_than_a_wrong_one() {
        let mut metadata = HashMap::new();
        metadata.insert("mpris:length".to_owned(), owned(ZValue::from("not a number")));
        assert_eq!(metadata_i64(&metadata, "mpris:length"), None);
    }

    #[test]
    fn artist_is_read_from_the_specified_array_and_from_a_bare_string() {
        let mut metadata = HashMap::new();
        metadata.insert(
            "xesam:artist".to_owned(),
            owned(ZValue::from(vec!["First".to_owned(), "Second".to_owned()])),
        );
        assert_eq!(metadata_first_of_list(&metadata, "xesam:artist"), Some("First".into()));

        // Non-conforming players publish a plain string.
        let mut metadata = HashMap::new();
        metadata.insert("xesam:artist".to_owned(), owned(ZValue::from("Solo")));
        assert_eq!(metadata_first_of_list(&metadata, "xesam:artist"), Some("Solo".into()));
    }

    #[test]
    fn an_empty_artist_list_yields_no_artist() {
        let mut metadata = HashMap::new();
        metadata.insert(
            "xesam:artist".to_owned(),
            owned(ZValue::from(Vec::<String>::new())),
        );
        assert_eq!(metadata_first_of_list(&metadata, "xesam:artist"), None);
    }

    #[test]
    fn discovery_matches_only_the_mpris_bus_prefix() {
        let names = [
            "org.mpris.MediaPlayer2.lollypop",
            "org.mpris.MediaPlayer2.firefox.instance_1_9",
            "org.freedesktop.Notifications",
            "org.mpris.NotMediaPlayer2.thing",
            "com.example.MediaPlayer2",
        ];
        let matched: Vec<_> = names
            .iter()
            .filter(|name| name.starts_with(MPRIS_BUS_PREFIX))
            .collect();
        assert_eq!(matched.len(), 2);
        // No application is special-cased: the prefix is the whole rule.
        assert!(matched.iter().any(|n| n.contains("lollypop")));
        assert!(matched.iter().any(|n| n.contains("firefox")));
    }
}
