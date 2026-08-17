use rand::Rng;

pub fn generate_nonce() -> Vec<u8> {
    let mut nonce = vec![0; 32];
    rand::rng().fill_bytes(&mut nonce);
    nonce
}

/// Generates a cryptographically random 32-byte Relay proof challenge nonce.
pub fn generate_nonce_32() -> [u8; 32] {
    let mut nonce = [0; 32];
    rand::rng().fill_bytes(&mut nonce);
    nonce
}

pub fn validate_nonce(nonce: &[u8]) -> bool {
    nonce.len() >= 16 && nonce.len() <= 128
}

#[cfg(test)]
mod tests {
    use super::generate_nonce_32;

    #[test]
    fn generated_nonce_32_has_fixed_length_and_varies() {
        let nonces: Vec<_> = (0..8).map(|_| generate_nonce_32()).collect();

        assert!(nonces.iter().all(|nonce| nonce.len() == 32));
        assert!(nonces.windows(2).any(|pair| pair[0] != pair[1]));
    }
}
