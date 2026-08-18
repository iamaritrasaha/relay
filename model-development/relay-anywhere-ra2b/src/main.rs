use std::sync::Arc;

use anyhow::Result;
use clap::{Parser, ValueEnum};
use relay_anywhere_ra2b::{
    Ra2bCancellation, Ra2bPathPreference, Ra2bPeerMaterial, Ra2bPhase, Ra2bRole, parse_invite,
    run_proof,
};

#[derive(Clone, Copy, Debug, ValueEnum)]
enum PathArg {
    Auto,
    Direct,
    Relay,
}

impl From<PathArg> for Ra2bPathPreference {
    fn from(value: PathArg) -> Self {
        match value {
            PathArg::Auto => Self::Auto,
            PathArg::Direct => Self::ForceDirect,
            PathArg::Relay => Self::ForceRelay,
        }
    }
}

#[derive(Parser, Debug)]
#[command(
    name = "relay-anywhere-ra2b",
    about = "Relay Anywhere RA2B Linux development harness (optional CLI; Flutter RA2B app is preferred)"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Parser, Debug)]
enum Command {
    /// Wait for a joiner and receive the proof payload.
    Responder {
        /// Expected RelayId of the remote initiator (uppercase hex, 64 chars).
        /// Omit to accept any authenticated client RelayId.
        #[arg(long)]
        expected_client_relay_id: Option<String>,
        #[arg(long, value_enum, default_value_t = PathArg::Auto)]
        path: PathArg,
    },
    /// Connect using a pasted RA2B invite or a raw endpoint descriptor.
    Initiator {
        /// Combined RA2B invite string from the host UI.
        #[arg(long)]
        invite: Option<String>,
        /// JSON endpoint descriptor (legacy). Prefer `--invite`.
        #[arg(long)]
        endpoint: Option<String>,
        /// Expected RelayId of the remote responder. Required with `--endpoint`.
        #[arg(long)]
        expected_server_relay_id: Option<String>,
        #[arg(long, value_enum, default_value_t = PathArg::Auto)]
        path: PathArg,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("info")
        .try_init()
        .ok();

    let cli = Cli::parse();
    match cli.command {
        Command::Responder {
            expected_client_relay_id,
            path,
        } => run_responder(expected_client_relay_id, path.into()).await,
        Command::Initiator {
            invite,
            endpoint,
            expected_server_relay_id,
            path,
        } => run_initiator(invite, endpoint, expected_server_relay_id, path.into()).await,
    }
}

async fn run_responder(
    expected_client_relay_id: Option<String>,
    path: Ra2bPathPreference,
) -> Result<()> {
    let peer = Ra2bPeerMaterial::generate(expected_client_relay_id)?;
    println!("LOCAL_RELAY_ID={}", peer.relay_id);
    let cancellation = Ra2bCancellation::new();
    let result = run_proof(
        Ra2bRole::Responder,
        peer,
        path,
        &cancellation,
        Arc::new(|phase| match phase {
            Ra2bPhase::EndpointReady { invite, .. } => {
                println!("INVITE={invite}");
                println!("Paste INVITE into the RA2B Flutter Join screen.");
            }
            Ra2bPhase::WaitingForConnection => println!("STATUS=waiting_for_connection"),
            Ra2bPhase::IrohConnected => println!("STATUS=iroh_connected"),
            Ra2bPhase::TlsAuthenticated => println!("STATUS=tls_authenticated"),
            Ra2bPhase::RelayIdentityAuthenticated { remote_relay_id } => {
                println!("STATUS=relay_identity_authenticated remote={remote_relay_id}")
            }
            Ra2bPhase::Transferring { bytes, total } => {
                println!("STATUS=transferring bytes={bytes} total={total}");
            }
            Ra2bPhase::Failed { message, category } => {
                println!("STATUS=failed category={category} message={message}")
            }
            Ra2bPhase::Cancelled => println!("STATUS=cancelled"),
            _ => {}
        }),
    )
    .await?;
    println!(
        "PASS path={} bytes={} sha256={} remote_relay_id={} duration_ms={}",
        result.path.as_str(),
        result.bytes,
        result.hash_hex,
        result.remote_relay_id,
        result.duration_ms
    );
    Ok(())
}

async fn run_initiator(
    invite: Option<String>,
    endpoint: Option<String>,
    expected_server_relay_id: Option<String>,
    path: Ra2bPathPreference,
) -> Result<()> {
    let (remote_endpoint, expected) = if let Some(invite) = invite {
        let parsed = parse_invite(&invite)?;
        (parsed.endpoint, parsed.host_relay_id)
    } else {
        let descriptor = endpoint.ok_or_else(|| {
            anyhow::anyhow!("provide --invite or --endpoint plus --expected-server-relay-id")
        })?;
        let expected = expected_server_relay_id.ok_or_else(|| {
            anyhow::anyhow!("--expected-server-relay-id is required with --endpoint")
        })?;
        (
            relay_anywhere_ra2b::decode_endpoint_addr(&descriptor)?,
            expected,
        )
    };
    let peer = Ra2bPeerMaterial::generate(Some(expected))?;
    println!("LOCAL_RELAY_ID={}", peer.relay_id);
    let cancellation = Ra2bCancellation::new();
    let result = run_proof(
        Ra2bRole::Initiator { remote_endpoint },
        peer,
        path,
        &cancellation,
        Arc::new(|phase| match phase {
            Ra2bPhase::Connecting => println!("STATUS=connecting"),
            Ra2bPhase::IrohConnected => println!("STATUS=iroh_connected"),
            Ra2bPhase::TlsAuthenticated => println!("STATUS=tls_authenticated"),
            Ra2bPhase::RelayIdentityAuthenticated { remote_relay_id } => {
                println!("STATUS=relay_identity_authenticated remote={remote_relay_id}")
            }
            Ra2bPhase::Transferring { bytes, total } => {
                println!("STATUS=transferring bytes={bytes} total={total}");
            }
            Ra2bPhase::Failed { message, category } => {
                println!("STATUS=failed category={category} message={message}")
            }
            Ra2bPhase::Cancelled => println!("STATUS=cancelled"),
            _ => {}
        }),
    )
    .await?;
    println!(
        "PASS path={} bytes={} sha256={} remote_relay_id={} duration_ms={}",
        result.path.as_str(),
        result.bytes,
        result.hash_hex,
        result.remote_relay_id,
        result.duration_ms
    );
    Ok(())
}
