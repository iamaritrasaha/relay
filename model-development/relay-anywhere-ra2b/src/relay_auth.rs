use std::sync::Arc;

use localsend::crypto::{
    relay_identity::RelayIdentity,
    relay_identity_proof::{
        PROOF_LEN, RelayIdentityProofV1, RelayProofRole, create_relay_identity_proof,
        verify_relay_identity_proof,
    },
};
use rand::RngCore;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

const NONCE_LEN: usize = 32;
const AUTH_OK: u8 = 0xa1;

#[derive(Clone)]
pub struct RelayAuthPeer {
    pub identity: Arc<RelayIdentity>,
    pub relay_id: String,
    pub cert_fingerprint: [u8; 32],
}

impl RelayAuthPeer {
    pub fn new(identity: RelayIdentity, cert_fingerprint: [u8; 32]) -> anyhow::Result<Self> {
        Self::from_arc(Arc::new(identity), cert_fingerprint)
    }

    pub fn from_arc(
        identity: Arc<RelayIdentity>,
        cert_fingerprint: [u8; 32],
    ) -> anyhow::Result<Self> {
        let relay_id = identity.relay_id()?;
        Ok(Self {
            relay_id,
            identity,
            cert_fingerprint,
        })
    }
}

pub const IDENTITY_REJECTED: &str = "IDENTITY_REJECTED";

pub async fn authenticate_client<S>(
    stream: &mut S,
    own: &RelayAuthPeer,
    expected_server_relay_id: &str,
    observed_server_cert_fingerprint: [u8; 32],
) -> anyhow::Result<String>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut server_nonce = [0_u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut server_nonce);
    stream.write_all(&server_nonce).await?;
    stream.flush().await?;

    let mut server_proof_bytes = [0_u8; PROOF_LEN];
    stream.read_exact(&mut server_proof_bytes).await?;
    let server_proof = RelayIdentityProofV1::decode(&server_proof_bytes)?;
    if server_proof.nonce != server_nonce {
        anyhow::bail!("server Relay proof challenge mismatch");
    }
    let verified_server = verify_relay_identity_proof(
        &server_proof,
        RelayProofRole::Server,
        observed_server_cert_fingerprint,
    )?;
    if verified_server != expected_server_relay_id {
        anyhow::bail!("{IDENTITY_REJECTED}: authoritative server RelayId mismatch");
    }
    tracing::info!(target: "ra2b", "SERVER_PROOF_OK");
    eprintln!("RA2B SERVER_PROOF_OK");

    let mut client_nonce = [0_u8; NONCE_LEN];
    stream.read_exact(&mut client_nonce).await?;
    let client_proof = create_relay_identity_proof(
        &own.identity,
        RelayProofRole::Client,
        client_nonce,
        own.cert_fingerprint,
    )?;
    tracing::info!(target: "ra2b", "CLIENT_PROOF_SENT");
    eprintln!("RA2B CLIENT_PROOF_SENT");
    stream.write_all(&client_proof.encode()).await?;
    stream.flush().await?;
    if stream.read_u8().await? != AUTH_OK {
        anyhow::bail!("{IDENTITY_REJECTED}: server rejected Relay authentication");
    }
    Ok(verified_server)
}

pub async fn authenticate_server<S>(
    stream: &mut S,
    own: &RelayAuthPeer,
    expected_client_relay_id: Option<&str>,
    observed_client_cert_fingerprint: [u8; 32],
) -> anyhow::Result<String>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let mut server_nonce = [0_u8; NONCE_LEN];
    stream.read_exact(&mut server_nonce).await?;
    let proof = create_relay_identity_proof(
        &own.identity,
        RelayProofRole::Server,
        server_nonce,
        own.cert_fingerprint,
    )?;
    tracing::info!(target: "ra2b", "SERVER_PROOF_SENT");
    eprintln!("RA2B SERVER_PROOF_SENT");
    stream.write_all(&proof.encode()).await?;

    let mut client_nonce = [0_u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut client_nonce);
    stream.write_all(&client_nonce).await?;
    stream.flush().await?;

    let mut client_proof_bytes = [0_u8; PROOF_LEN];
    stream.read_exact(&mut client_proof_bytes).await?;
    let client_proof = RelayIdentityProofV1::decode(&client_proof_bytes)?;
    if client_proof.nonce != client_nonce {
        anyhow::bail!("client Relay proof challenge mismatch");
    }
    let verified_client = verify_relay_identity_proof(
        &client_proof,
        RelayProofRole::Client,
        observed_client_cert_fingerprint,
    )?;
    if let Some(expected) = expected_client_relay_id
        && verified_client != expected
    {
        anyhow::bail!("{IDENTITY_REJECTED}: authoritative client RelayId mismatch");
    }
    tracing::info!(target: "ra2b", "CLIENT_PROOF_OK");
    eprintln!("RA2B CLIENT_PROOF_OK");
    stream.write_u8(AUTH_OK).await?;
    stream.flush().await?;
    Ok(verified_client)
}

#[cfg(test)]
mod tests {
    use localsend::crypto::{
        relay_identity::RelayIdentity,
        relay_identity_proof::{
            RelayProofRole, create_relay_identity_proof, verify_relay_identity_proof,
        },
    };

    #[test]
    fn relay_proof_rejects_wrong_expected_relay_id() {
        let identity = RelayIdentity::generate();
        let expected = identity.relay_id().unwrap();
        let proof =
            create_relay_identity_proof(&identity, RelayProofRole::Server, [1_u8; 32], [2_u8; 32])
                .unwrap();
        let verified =
            verify_relay_identity_proof(&proof, RelayProofRole::Server, [2_u8; 32]).unwrap();
        assert_eq!(verified, expected);
        assert_ne!(verified, "0".repeat(64));
    }
}
