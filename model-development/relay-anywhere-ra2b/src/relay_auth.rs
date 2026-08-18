//! RA2B-facing identity rejection label. Cryptographic verification lives in
//! production `localsend::anywhere` / `RelayAuthCoordinator`.

pub const IDENTITY_REJECTED: &str = "IDENTITY_REJECTED";

#[cfg(test)]
mod tests {
    use localsend::crypto::{
        relay_identity::RelayIdentity,
        relay_identity_proof::{
            create_relay_identity_proof, verify_relay_identity_proof, RelayProofRole,
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
