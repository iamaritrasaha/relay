# Relay Anywhere RA2A

Linux-only, non-production proof harness for the approved Relay Anywhere RA1 architecture.

It uses three ephemeral Iroh EndpointIds for routing (A, B, and adversarial C), three independent Relay identities for product trust, a memory-only capability rendezvous, stock self-hosted `iroh-relay` 1.0.3, and inner Relay TLS plus `RelayIdentityProofV1` over an Iroh QUIC bidirectional stream.

Each inner-TLS endpoint owns an independent self-signed certificate. The harness accepts a structurally usable TLS peer certificate so that Relay proof—not a fixture CA—remains authoritative. The proof verifies each `RelayIdentityProofV1` against the certificate fingerprint observed on that exact TLS stream and independently checks the expected RelayId.

Run the complete manual proof:

```bash
cargo run --locked --release
```

Run only the focused proof tests and checks:

```bash
cargo test --locked
cargo fmt --check
cargo clippy --locked --all-targets -- -D warnings
```

The harness does not provide Flutter UI, production rendezvous, production file transfer, public relay use, accounts, persistence, or Android integration.

The forced-relay test validates Relay end-to-end identity and content security over an untrusted relay path. Its local Iroh test relay uses insecure relay-server TLS verification, so it does **not** validate deployment-time relay server certificate verification.
