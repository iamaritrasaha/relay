//! MPRIS media control, host side.
//!
//! Relay Linux is the *player host*: the phone's `MprisPlugin` sends
//! `kdeconnect.mpris.request` packets, and Relay answers with
//! `kdeconnect.mpris` state built from whatever MPRIS players are on the
//! session bus.
//!
//! Nothing here knows about transports. The request arrives through the shared
//! packet dispatcher and the answer goes back over the route it came in on, so
//! the identical code serves a phone on the LAN and a phone on mobile data --
//! there is no WAN-specific media path, by construction.
//!
//! The split is deliberate: [`PlayerSnapshot`], [`PlayerCommand`] and the
//! mapping between them and KDE packets are pure and unit-tested, while
//! [`dbus`] holds the only code that needs a real session bus.

use std::future::Future;
use std::pin::Pin;

use crate::kdeconnect::packet::{MprisBody, MprisRequestBody};

#[cfg(all(target_os = "linux", feature = "mpris"))]
pub mod dbus;

pub type HostFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// A snapshot of one MPRIS player, in the units KDE Connect speaks
/// (milliseconds, 0-100 volume) rather than MPRIS's own (microseconds,
/// 0.0-1.0). Converting at the edge keeps the unit mistakes in one place.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct PlayerSnapshot {
    /// The name the phone sees and addresses this player by (MPRIS `Identity`).
    pub name: String,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub url: Option<String>,
    pub album_art_url: Option<String>,
    pub loop_status: Option<String>,
    pub shuffle: Option<bool>,
    /// 0-100, as KDE Connect expects.
    pub volume: Option<i64>,
    pub length_ms: Option<i64>,
    pub position_ms: Option<i64>,
    pub is_playing: bool,
    pub can_play: bool,
    pub can_pause: bool,
    pub can_go_next: bool,
    pub can_go_previous: bool,
    pub can_seek: bool,
}

impl PlayerSnapshot {
    /// Renders this snapshot as the `kdeconnect.mpris` body the phone parses.
    pub fn to_body(&self) -> MprisBody {
        MprisBody {
            player: Some(self.name.clone()),
            title: self.title.clone(),
            artist: self.artist.clone(),
            album: self.album.clone(),
            url: self.url.clone(),
            album_art_url: self.album_art_url.clone(),
            loop_status: self.loop_status.clone(),
            shuffle: self.shuffle,
            volume: self.volume,
            length: self.length_ms,
            pos: self.position_ms,
            is_playing: Some(self.is_playing),
            can_play: Some(self.can_play),
            can_pause: Some(self.can_pause),
            can_go_next: Some(self.can_go_next),
            can_go_previous: Some(self.can_go_previous),
            can_seek: Some(self.can_seek),
        }
    }
}

/// One control instruction for a player, already validated.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PlayerCommand {
    Play,
    Pause,
    PlayPause,
    Stop,
    Next,
    Previous,
    /// 0-100.
    SetVolume(i64),
    /// Absolute position, milliseconds.
    SetPositionMs(i64),
    /// Relative offset, microseconds (MPRIS `Seek`'s own unit).
    SeekUs(i64),
    SetLoopStatus(String),
    SetShuffle(bool),
}

/// MPRIS `LoopStatus` is a closed enum on the bus; anything else makes the
/// property write fail. Filtering here keeps remote text off the bus entirely.
const VALID_LOOP_STATUS: [&str; 3] = ["None", "Track", "Playlist"];

impl PlayerCommand {
    /// Extracts every control instruction carried by one request packet.
    ///
    /// A single packet may carry more than one (the phone's status refresh
    /// bundles `requestNowPlaying` with `requestVolume`, and nothing stops it
    /// bundling a command too), so this returns all of them in a stable order
    /// rather than picking one.
    ///
    /// Unknown actions and out-of-range values are dropped rather than passed
    /// to D-Bus: the phone is trusted to be the user's, but a malformed or
    /// hostile packet must not become an arbitrary bus write.
    pub fn from_request(request: &MprisRequestBody) -> Vec<PlayerCommand> {
        let mut commands = Vec::new();
        if let Some(action) = request.action.as_deref() {
            match action {
                "Play" => commands.push(PlayerCommand::Play),
                "Pause" => commands.push(PlayerCommand::Pause),
                "PlayPause" => commands.push(PlayerCommand::PlayPause),
                "Stop" => commands.push(PlayerCommand::Stop),
                "Next" => commands.push(PlayerCommand::Next),
                "Previous" => commands.push(PlayerCommand::Previous),
                other => {
                    tracing::warn!("[Relay MPRIS] ignoring unknown action: {other}");
                }
            }
        }
        if let Some(volume) = request.set_volume {
            if (0..=100).contains(&volume) {
                commands.push(PlayerCommand::SetVolume(volume));
            } else {
                tracing::warn!("[Relay MPRIS] ignoring out-of-range volume");
            }
        }
        if let Some(position) = request.set_position {
            if position >= 0 {
                commands.push(PlayerCommand::SetPositionMs(position));
            }
        }
        if let Some(offset) = request.seek {
            commands.push(PlayerCommand::SeekUs(offset));
        }
        if let Some(status) = request.set_loop_status.as_deref() {
            if VALID_LOOP_STATUS.contains(&status) {
                commands.push(PlayerCommand::SetLoopStatus(status.to_owned()));
            } else {
                tracing::warn!("[Relay MPRIS] ignoring unknown loop status");
            }
        }
        if let Some(shuffle) = request.set_shuffle {
            commands.push(PlayerCommand::SetShuffle(shuffle));
        }
        commands
    }
}

/// The set of MPRIS players Relay can see and drive.
///
/// Abstracted so the packet handling can be tested against a fake host without
/// a session bus, and so a non-Linux build simply has no implementation rather
/// than needing conditional handling further up.
pub trait MediaPlayerHost: Send + Sync {
    /// Every player currently on the bus, in a stable order.
    fn players(&self) -> HostFuture<'_, Vec<PlayerSnapshot>>;

    /// One player by the name the phone addressed, or `None` if it is gone.
    fn player<'a>(&'a self, name: &'a str) -> HostFuture<'a, Option<PlayerSnapshot>>;

    /// Applies one command to one player. An unknown player is an error, never
    /// a silent no-op against some other player.
    fn control<'a>(&'a self, name: &'a str, command: PlayerCommand) -> HostFuture<'a, anyhow::Result<()>>;

    /// A stream of "something changed" ticks, used to push fresh state to
    /// phones instead of leaving their UI stale until they next ask.
    ///
    /// Deliberately carries no payload: the receiver re-reads the players it
    /// cares about, which keeps this correct when several properties change at
    /// once and avoids modelling D-Bus's per-property signals up here. Returning
    /// `None` means "no change notifications available", and the phone then sees
    /// state only when it requests it.
    fn subscribe(&self) -> HostFuture<'_, Option<tokio::sync::mpsc::Receiver<()>>> {
        Box::pin(async move { None })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Map, Value};

    fn request(pairs: &[(&str, Value)]) -> MprisRequestBody {
        let mut body = Map::new();
        for (key, value) in pairs {
            body.insert((*key).to_owned(), value.clone());
        }
        crate::kdeconnect::packet::NetworkPacket::new("kdeconnect.mpris.request", body)
            .as_mpris_request()
            .expect("valid request")
    }

    #[test]
    fn each_transport_control_action_maps_to_its_command() {
        for (action, expected) in [
            ("Play", PlayerCommand::Play),
            ("Pause", PlayerCommand::Pause),
            ("PlayPause", PlayerCommand::PlayPause),
            ("Stop", PlayerCommand::Stop),
            ("Next", PlayerCommand::Next),
            ("Previous", PlayerCommand::Previous),
        ] {
            let parsed = request(&[("player", "p".into()), ("action", action.into())]);
            assert_eq!(PlayerCommand::from_request(&parsed), vec![expected]);
        }
    }

    #[test]
    fn an_unknown_action_produces_no_command_at_all() {
        let parsed = request(&[("player", "p".into()), ("action", "SelfDestruct".into())]);
        assert!(PlayerCommand::from_request(&parsed).is_empty());
    }

    #[test]
    fn volume_outside_zero_to_one_hundred_is_refused() {
        for bad in [-1_i64, 101, i64::MAX] {
            let parsed = request(&[("player", "p".into()), ("setVolume", bad.into())]);
            assert!(PlayerCommand::from_request(&parsed).is_empty(), "{bad} accepted");
        }
        let parsed = request(&[("player", "p".into()), ("setVolume", 50.into())]);
        assert_eq!(PlayerCommand::from_request(&parsed), vec![PlayerCommand::SetVolume(50)]);
    }

    #[test]
    fn only_the_three_mpris_loop_statuses_are_accepted() {
        for good in ["None", "Track", "Playlist"] {
            let parsed = request(&[("player", "p".into()), ("setLoopStatus", good.into())]);
            assert_eq!(
                PlayerCommand::from_request(&parsed),
                vec![PlayerCommand::SetLoopStatus(good.to_owned())]
            );
        }
        let parsed = request(&[("player", "p".into()), ("setLoopStatus", "Forever".into())]);
        assert!(PlayerCommand::from_request(&parsed).is_empty());
    }

    #[test]
    fn a_negative_absolute_position_is_refused_but_a_negative_seek_is_not() {
        // SetPosition is absolute so a negative value is nonsense; Seek is a
        // relative offset and seeking backwards is normal.
        let parsed = request(&[("player", "p".into()), ("SetPosition", (-5_i64).into())]);
        assert!(PlayerCommand::from_request(&parsed).is_empty());

        let parsed = request(&[("player", "p".into()), ("Seek", (-5_000_000_i64).into())]);
        assert_eq!(PlayerCommand::from_request(&parsed), vec![PlayerCommand::SeekUs(-5_000_000)]);
    }

    #[test]
    fn a_request_with_no_instruction_is_rejected_as_malformed() {
        let mut body = Map::new();
        body.insert("player".into(), "p".into());
        let packet =
            crate::kdeconnect::packet::NetworkPacket::new("kdeconnect.mpris.request", body);
        assert!(packet.as_mpris_request().is_err());
    }

    #[test]
    fn a_wrong_packet_type_is_not_read_as_an_mpris_request() {
        let packet = crate::kdeconnect::packet::NetworkPacket::new(
            "kdeconnect.mpris",
            Map::new(),
        );
        assert!(packet.as_mpris_request().is_err());
    }

    #[test]
    fn an_over_long_player_name_is_refused_before_it_reaches_the_bus() {
        let mut body = Map::new();
        body.insert("player".into(), "x".repeat(500).into());
        body.insert("requestNowPlaying".into(), true.into());
        let packet =
            crate::kdeconnect::packet::NetworkPacket::new("kdeconnect.mpris.request", body);
        assert!(packet.as_mpris_request().is_err());
    }

    #[test]
    fn a_status_refresh_bundles_now_playing_and_volume_without_any_control() {
        let parsed = request(&[
            ("player", "p".into()),
            ("requestNowPlaying", true.into()),
            ("requestVolume", true.into()),
        ]);
        assert!(parsed.request_now_playing);
        assert!(parsed.request_volume);
        assert!(PlayerCommand::from_request(&parsed).is_empty());
    }

    #[test]
    fn a_snapshot_serializes_every_field_the_android_plugin_reads() {
        let snapshot = PlayerSnapshot {
            name: "Lollypop".into(),
            title: Some("Title".into()),
            artist: Some("Artist".into()),
            album: Some("Album".into()),
            url: Some("file:///song.flac".into()),
            album_art_url: Some("file:///art.png".into()),
            loop_status: Some("Track".into()),
            shuffle: Some(true),
            volume: Some(42),
            length_ms: Some(210_000),
            position_ms: Some(1_500),
            is_playing: true,
            can_play: true,
            can_pause: true,
            can_go_next: true,
            can_go_previous: false,
            can_seek: true,
        };

        let packet = snapshot.to_body().to_packet();
        assert_eq!(packet.packet_type, "kdeconnect.mpris");
        let body = &packet.body;
        assert_eq!(body.get("player").and_then(Value::as_str), Some("Lollypop"));
        assert_eq!(body.get("title").and_then(Value::as_str), Some("Title"));
        assert_eq!(body.get("artist").and_then(Value::as_str), Some("Artist"));
        assert_eq!(body.get("album").and_then(Value::as_str), Some("Album"));
        assert_eq!(body.get("albumArtUrl").and_then(Value::as_str), Some("file:///art.png"));
        assert_eq!(body.get("loopStatus").and_then(Value::as_str), Some("Track"));
        assert_eq!(body.get("shuffle").and_then(Value::as_bool), Some(true));
        assert_eq!(body.get("volume").and_then(Value::as_i64), Some(42));
        assert_eq!(body.get("length").and_then(Value::as_i64), Some(210_000));
        assert_eq!(body.get("pos").and_then(Value::as_i64), Some(1_500));
        assert_eq!(body.get("isPlaying").and_then(Value::as_bool), Some(true));
        assert_eq!(body.get("canPlay").and_then(Value::as_bool), Some(true));
        assert_eq!(body.get("canPause").and_then(Value::as_bool), Some(true));
        assert_eq!(body.get("canGoNext").and_then(Value::as_bool), Some(true));
        assert_eq!(body.get("canGoPrevious").and_then(Value::as_bool), Some(false));
        assert_eq!(body.get("canSeek").and_then(Value::as_bool), Some(true));
    }

    #[test]
    fn an_absent_metadata_field_is_omitted_rather_than_sent_as_empty() {
        // The Android plugin falls back to its *previous* value for an absent
        // key, so sending "" would actively erase good metadata on the phone.
        let snapshot = PlayerSnapshot {
            name: "Player".into(),
            ..Default::default()
        };
        let packet = snapshot.to_body().to_packet();
        assert!(!packet.body.contains_key("title"));
        assert!(!packet.body.contains_key("artist"));
        assert!(!packet.body.contains_key("albumArtUrl"));
        assert!(!packet.body.contains_key("volume"));
    }

    #[test]
    fn the_player_list_packet_carries_every_player_and_disclaims_art_payloads() {
        let packet = MprisBody::player_list(&["A".to_owned(), "B".to_owned()]);
        assert_eq!(packet.packet_type, "kdeconnect.mpris");
        let list = packet.body.get("playerList").and_then(Value::as_array).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].as_str(), Some("A"));
        assert_eq!(
            packet.body.get("supportAlbumArtPayload").and_then(Value::as_bool),
            Some(false),
            "claiming payload support would make the phone wait for bytes Relay never sends"
        );
    }

    #[test]
    fn an_empty_player_list_is_still_a_well_formed_answer() {
        let packet = MprisBody::player_list(&[]);
        assert_eq!(
            packet.body.get("playerList").and_then(Value::as_array).map(Vec::len),
            Some(0)
        );
    }
}
