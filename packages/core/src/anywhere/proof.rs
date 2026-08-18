//! Mutual RelayIdentityProofV1 over an already-established inner TLS stream.
//!
//! No transfer payload is written by this module.

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use super::error::{AnywhereError, TransportStage};
use crate::crypto::nonce::generate_nonce_32;
use crate::crypto::relay_identity::RelayIdentity;
use crate::crypto::relay_identity_proof::{
    create_relay_identity_proof, RelayIdentityProofV1, RelayProofRole, PROOF_LEN,
};
use crate::relay::{AuthenticatedRelaySession, PathDescriptor, RelayAuthCoordinator, RelayId};

const AUTH_OK: u8 = 0xa1;

/// Initiator: challenge the responder's Server-role proof, then send Client-role proof.
pub async fn authenticate_initiator<S>(
    stream: &mut S,
    identity: &RelayIdentity,
    own_cert_fingerprint: [u8; 32],
    expected_remote: &RelayId,
    observed_server_cert_fingerprint: [u8; 32],
    path: PathDescriptor,
) -> Result<AuthenticatedRelaySession, AnywhereError>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let coordinator = RelayAuthCoordinator::new(
        RelayId::from_local_identity(identity).map_err(|_| AnywhereError::RelayProof)?,
    );

    let server_nonce = generate_nonce_32();
    stream
        .write_all(&server_nonce)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    stream
        .flush()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;

    let mut server_proof_bytes = [0_u8; PROOF_LEN];
    stream
        .read_exact(&mut server_proof_bytes)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    let server_proof =
        RelayIdentityProofV1::decode(&server_proof_bytes).map_err(|_| AnywhereError::RelayProof)?;
    if server_proof.nonce != server_nonce {
        return Err(AnywhereError::RelayProof);
    }

    let session = coordinator
        .complete_anywhere_initiator(
            &server_proof,
            observed_server_cert_fingerprint,
            expected_remote,
            path,
        )
        .map_err(AnywhereError::from_auth)?;

    let mut client_nonce = [0_u8; 32];
    stream
        .read_exact(&mut client_nonce)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    let client_proof = create_relay_identity_proof(
        identity,
        RelayProofRole::Client,
        client_nonce,
        own_cert_fingerprint,
    )
    .map_err(|_| AnywhereError::RelayProof)?;
    stream
        .write_all(&client_proof.encode())
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    stream
        .flush()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    let ack = stream
        .read_u8()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    if ack != AUTH_OK {
        return Err(AnywhereError::RelayProof);
    }
    Ok(session)
}

/// Responder: send Server-role proof, then verify the initiator's Client-role proof.
pub async fn authenticate_server<S>(
    stream: &mut S,
    identity: &RelayIdentity,
    own_cert_fingerprint: [u8; 32],
    expected_remote: Option<&RelayId>,
    observed_client_cert_fingerprint: [u8; 32],
    path: PathDescriptor,
) -> Result<AuthenticatedRelaySession, AnywhereError>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let coordinator = RelayAuthCoordinator::new(
        RelayId::from_local_identity(identity).map_err(|_| AnywhereError::RelayProof)?,
    );

    let mut server_nonce = [0_u8; 32];
    stream
        .read_exact(&mut server_nonce)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    let proof = create_relay_identity_proof(
        identity,
        RelayProofRole::Server,
        server_nonce,
        own_cert_fingerprint,
    )
    .map_err(|_| AnywhereError::RelayProof)?;
    stream
        .write_all(&proof.encode())
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;

    let client_nonce = generate_nonce_32();
    stream
        .write_all(&client_nonce)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    stream
        .flush()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;

    let mut client_proof_bytes = [0_u8; PROOF_LEN];
    stream
        .read_exact(&mut client_proof_bytes)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    let client_proof =
        RelayIdentityProofV1::decode(&client_proof_bytes).map_err(|_| AnywhereError::RelayProof)?;
    if client_proof.nonce != client_nonce {
        return Err(AnywhereError::RelayProof);
    }

    let session = coordinator
        .complete_anywhere_responder(
            &client_proof,
            observed_client_cert_fingerprint,
            expected_remote,
            path,
        )
        .map_err(AnywhereError::from_auth)?;

    stream
        .write_u8(AUTH_OK)
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    stream
        .flush()
        .await
        .map_err(|error| AnywhereError::transport(TransportStage::ProofIo, error))?;
    Ok(session)
}
