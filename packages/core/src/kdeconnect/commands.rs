//! RunCommand: a Desktop-owned allow-list of shell commands a paired phone may
//! trigger *by id*.
//!
//! # Security model
//!
//! The phone never supplies command text. The only remote input that reaches
//! this module is an opaque id string, which is used solely as a lookup key
//! into a list the desktop user configured locally. A lookup miss is a hard
//! rejection -- there is no fallback, no fuzzy match, and no path by which a
//! `kdeconnect.runcommand.request` packet can introduce a new command.
//!
//! Concretely, execution requires all of:
//!
//! 1. the requesting logical device is in the KDE trust store,
//! 2. the id names an entry that already exists locally,
//! 3. that entry is enabled.
//!
//! Transport is deliberately absent from that list: a request arriving over
//! Relay WAN is subject to exactly these checks and no others, because the WAN
//! layer has already bound the connection to a trusted KDE device id before any
//! packet is dispatched (an unknown Iroh `EndpointId` is refused before its
//! first byte is read). WAN therefore cannot broaden what a phone may run.

use std::sync::Mutex;

use serde::{Deserialize, Serialize};

/// One locally configured command.
///
/// `id` is generated once, on creation, and persisted with the entry, so it
/// stays stable across restarts -- the phone caches ids and would otherwise be
/// left holding stale keys after every launch.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RunCommandEntry {
    pub id: String,
    pub name: String,
    /// The command line, exactly as the desktop user typed it. Never built from
    ///, or concatenated with, anything received from a phone.
    pub command: String,
    pub enabled: bool,
}

impl RunCommandEntry {
    /// Creates an entry with a fresh stable id.
    pub fn new(name: impl Into<String>, command: impl Into<String>, enabled: bool) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            name: name.into(),
            command: command.into(),
            enabled,
        }
    }
}

/// Why a run request was refused. Kept as distinct variants so the refusal
/// reason can be logged precisely without ever logging the command itself.
#[derive(Clone, Copy, Debug, Eq, PartialEq, thiserror::Error)]
pub enum RunCommandRejection {
    #[error("requesting device is not paired")]
    DeviceNotTrusted,
    #[error("no command with that id is configured")]
    UnknownCommand,
    #[error("command is disabled")]
    CommandDisabled,
}

/// The desktop's configured command list.
#[derive(Default)]
pub struct RunCommandRegistry {
    entries: Mutex<Vec<RunCommandEntry>>,
}

impl RunCommandRegistry {
    pub fn new(entries: Vec<RunCommandEntry>) -> Self {
        Self {
            entries: Mutex::new(entries),
        }
    }

    /// Replaces the whole list, as the settings UI does after an edit.
    pub fn replace(&self, entries: Vec<RunCommandEntry>) {
        *self.entries.lock().expect("RunCommandRegistry poisoned") = entries;
    }

    pub fn snapshot(&self) -> Vec<RunCommandEntry> {
        self.entries
            .lock()
            .expect("RunCommandRegistry poisoned")
            .clone()
    }

    /// The `(id, name, command)` triples advertised to a phone.
    ///
    /// Disabled entries are omitted entirely rather than sent with a flag: a
    /// command the user has switched off should not even be visible remotely.
    pub fn advertised(&self) -> Vec<(String, String, String)> {
        self.entries
            .lock()
            .expect("RunCommandRegistry poisoned")
            .iter()
            .filter(|entry| entry.enabled)
            .map(|entry| (entry.id.clone(), entry.name.clone(), entry.command.clone()))
            .collect()
    }

    /// Resolves a phone-supplied id to a command that may actually be run.
    ///
    /// `device_is_trusted` is passed in rather than looked up here so this stays
    /// a pure decision function -- see the tests, which exercise every refusal
    /// path without a running KDE session.
    pub fn resolve_for_execution(
        &self,
        id: &str,
        device_is_trusted: bool,
    ) -> Result<RunCommandEntry, RunCommandRejection> {
        if !device_is_trusted {
            return Err(RunCommandRejection::DeviceNotTrusted);
        }
        let entries = self.entries.lock().expect("RunCommandRegistry poisoned");
        let entry = entries
            .iter()
            .find(|entry| entry.id == id)
            .ok_or(RunCommandRejection::UnknownCommand)?;
        if !entry.enabled {
            return Err(RunCommandRejection::CommandDisabled);
        }
        Ok(entry.clone())
    }
}

/// Runs a locally configured command line.
///
/// Abstracted so tests can assert *what would have run* without running it, and
/// so the spawn policy lives in one place.
pub trait CommandRunner: Send + Sync {
    /// Spawns `command_line`. Must not block the caller: the KDE packet
    /// dispatcher awaits this inline, and a long-running command would
    /// otherwise stall every other packet on that link.
    fn spawn(&self, command_line: &str) -> anyhow::Result<()>;
}

/// Spawns through the user's shell, which is what KDE RunCommand entries assume
/// (they routinely contain pipes, redirections and `&&`).
///
/// This is only ever handed a string that came from local configuration; remote
/// input reaches it under no circumstances, which is what makes shell semantics
/// acceptable here. The child is fully detached from Relay's stdio so a chatty
/// command cannot fill Relay's pipes and block, and is explicitly *not* awaited
/// so the dispatcher returns immediately.
#[derive(Default)]
pub struct ShellCommandRunner;

impl CommandRunner for ShellCommandRunner {
    fn spawn(&self, command_line: &str) -> anyhow::Result<()> {
        use std::process::Stdio;
        let mut child = tokio::process::Command::new("sh")
            .arg("-c")
            .arg(command_line)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .kill_on_drop(false)
            .spawn()?;
        // Reap asynchronously so finished commands do not linger as zombies,
        // without making the caller wait for them.
        tokio::spawn(async move {
            let _ = child.wait().await;
        });
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex as StdMutex;

    /// Records what would have been spawned instead of spawning it.
    #[derive(Default)]
    struct RecordingRunner {
        spawned: StdMutex<Vec<String>>,
        fail: bool,
    }

    impl CommandRunner for RecordingRunner {
        fn spawn(&self, command_line: &str) -> anyhow::Result<()> {
            self.spawned.lock().unwrap().push(command_line.to_owned());
            if self.fail {
                anyhow::bail!("simulated spawn failure");
            }
            Ok(())
        }
    }

    fn registry() -> RunCommandRegistry {
        RunCommandRegistry::new(vec![
            RunCommandEntry {
                id: "cmd-enabled".into(),
                name: "Marker".into(),
                command: "touch /tmp/relay-marker".into(),
                enabled: true,
            },
            RunCommandEntry {
                id: "cmd-disabled".into(),
                name: "Disabled".into(),
                command: "echo nope".into(),
                enabled: false,
            },
        ])
    }

    #[test]
    fn only_enabled_commands_are_advertised_to_a_phone() {
        let advertised = registry().advertised();
        assert_eq!(advertised.len(), 1);
        assert_eq!(advertised[0].0, "cmd-enabled");
        assert_eq!(advertised[0].1, "Marker");
    }

    #[test]
    fn an_enabled_command_resolves_for_a_trusted_device() {
        let entry = registry().resolve_for_execution("cmd-enabled", true).unwrap();
        assert_eq!(entry.command, "touch /tmp/relay-marker");
    }

    #[test]
    fn a_disabled_command_is_refused_even_for_a_trusted_device() {
        assert_eq!(
            registry().resolve_for_execution("cmd-disabled", true).unwrap_err(),
            RunCommandRejection::CommandDisabled
        );
    }

    #[test]
    fn an_unknown_id_is_refused_rather_than_falling_back_to_any_command() {
        assert_eq!(
            registry().resolve_for_execution("cmd-does-not-exist", true).unwrap_err(),
            RunCommandRejection::UnknownCommand
        );
        assert_eq!(
            registry().resolve_for_execution("", true).unwrap_err(),
            RunCommandRejection::UnknownCommand
        );
    }

    #[test]
    fn an_untrusted_device_is_refused_before_the_id_is_even_looked_up() {
        // Refused for a *valid* id, so this is the trust check firing and not
        // an incidental lookup miss.
        assert_eq!(
            registry().resolve_for_execution("cmd-enabled", false).unwrap_err(),
            RunCommandRejection::DeviceNotTrusted
        );
    }

    #[test]
    fn command_text_supplied_by_a_phone_can_never_be_executed() {
        // The registry's only remote-facing input is an id. Text that looks like
        // a command is just a missing id, whatever it contains.
        let registry = registry();
        for hostile in [
            "rm -rf ~",
            "touch /tmp/relay-marker",
            "cmd-enabled; rm -rf ~",
            "../cmd-enabled",
            "CMD-ENABLED",
        ] {
            assert_eq!(
                registry.resolve_for_execution(hostile, true).unwrap_err(),
                RunCommandRejection::UnknownCommand,
                "{hostile} must not resolve"
            );
        }
    }

    #[test]
    fn resolution_returns_the_locally_configured_text_not_the_requested_id() {
        // What runs is always the configured string, so an id can only ever
        // select from the allow-list, never influence the content.
        let entry = registry().resolve_for_execution("cmd-enabled", true).unwrap();
        let runner = RecordingRunner::default();
        runner.spawn(&entry.command).unwrap();
        assert_eq!(runner.spawned.lock().unwrap().as_slice(), ["touch /tmp/relay-marker"]);
    }

    #[test]
    fn ids_are_unique_and_survive_a_serialization_round_trip() {
        let a = RunCommandEntry::new("A", "echo a", true);
        let b = RunCommandEntry::new("B", "echo b", true);
        assert_ne!(a.id, b.id);

        // Persistence keeps the id, which is what makes a phone's cached key
        // still valid after a desktop restart.
        let json = serde_json::to_string(&a).unwrap();
        let restored: RunCommandEntry = serde_json::from_str(&json).unwrap();
        assert_eq!(restored, a);

        let restored_registry = RunCommandRegistry::new(vec![restored]);
        assert_eq!(
            restored_registry.resolve_for_execution(&a.id, true).unwrap().command,
            "echo a"
        );
    }

    #[test]
    fn replacing_the_list_immediately_revokes_a_removed_command() {
        let registry = registry();
        assert!(registry.resolve_for_execution("cmd-enabled", true).is_ok());

        registry.replace(vec![]);

        assert_eq!(
            registry.resolve_for_execution("cmd-enabled", true).unwrap_err(),
            RunCommandRejection::UnknownCommand
        );
        assert!(registry.advertised().is_empty());
    }

    #[test]
    fn a_spawn_failure_is_reported_rather_than_panicking() {
        let runner = RecordingRunner {
            fail: true,
            ..Default::default()
        };
        // The error surfaces to the caller, which logs and carries on; nothing
        // here may unwind into the packet dispatcher.
        assert!(runner.spawn("false").is_err());
    }

    #[tokio::test]
    async fn the_real_runner_reports_a_spawn_failure_without_blocking_or_panicking() {
        let runner = ShellCommandRunner;
        // `sh -c` exists, so this spawns and then fails inside the shell -- the
        // spawn itself succeeds and Relay is unaffected by the exit status.
        assert!(runner.spawn("exit 7").is_ok());
        // A command that does not exist still only fails *inside* the shell.
        assert!(runner.spawn("relay-no-such-binary-xyz").is_ok());
    }
}
