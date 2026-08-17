# Relay Anywhere RA1 Internet Connectivity Architecture

Status: **RA1 architecture proposal — no production implementation**

Research date: **2026-08-18**

Repository baseline: `56dffd8854e912a3fea86f622fefb22b46f1bb64`

## 1. Executive recommendation

Keep Relay's proven LAN stack exactly as it is. Add an independent, provider-neutral **Anywhere path-establishment layer** whose leading proof substrate is pinned `iroh` 1.0.3: QUIC over UDP for direct connections, coordinated simultaneous hole punching using relay-observed addresses, and the stock, self-hosted `iroh-relay` 1.0.3 fallback when direct UDP is impossible. Iroh is a substrate candidate, not a new trust system: use an ephemeral online-session Iroh EndpointId for routing, then run an **inner, end-to-end Relay TLS channel and the existing Relay identity proof over one Iroh QUIC bidirectional stream**. A path is usable only after that proof returns the already-trusted RelayId. RA2A first proves this on Linux with a temporary memory-only capability rendezvous; RA2B performs physical Android/Linux validation only after RA2A passes. This gives Relay a single security invariant across LAN direct, Internet direct, and relay fallback while avoiding a rewrite of LAN discovery or HTTP transfer.

The recommendation deliberately borrows only pieces that fit Relay:

- From ICE: candidate gathering, simultaneous checks, IPv6 preference, explicit restart, and honest relay fallback—not the WebRTC media stack.
- From DERP: the relay forwards opaque bounded packets while endpoints retain end-to-end security—not Tailscale's account/control plane or WireGuard identity. RA2A uses Iroh's stock implementation of this inherited design, not a new Relay implementation.
- From Iroh: an integrated QUIC/hole-punch/relay path that already exposes Rust streams and self-hostable relay code—not Iroh discovery as Relay's device trust directory.
- From QUIC: TLS 1.3, multiplexed flow-controlled streams, path validation, and connection migration—not the false claim that QUIC by itself solves NAT traversal.

**Decision:** proceed in two gates. RA2A is a Linux/network proof using exactly `iroh = "=1.0.3"`, its stock/self-hosted pinned relay, two ephemeral Iroh EndpointIds, and the unchanged Relay TLS/proof contract inside QUIC. RA2B follows only if RA2A passes and proves the same path in Relay's Android Rust build on physical Android/Linux devices. Keep a plain Quinn + custom traversal provider possible, and do not accept Iroh for production until both gates provide the required evidence.

## 2. Current Relay constraints

The following are invariants, not migration targets:

- Android and Linux LAN discovery and transfer startup remain independent of Internet services.
- `packages/core` HTTP/TLS server and client behavior remains unchanged.
- Existing LocalSend/Relay files, folders, large-transfer, progress, cancel, and save-target behavior remains unchanged.
- The persistent Ed25519 `RelayIdentity`, its secure private-key storage, and `RelayId = SHA-256(canonical SPKI DER)` remain authoritative.
- `RelayIdentityProofV1` remains unchanged. It signs the role, single-use 32-byte challenge, RelayId digest, and SHA-256 fingerprint of the actual TLS certificate. The transport must supply the observed certificate fingerprint; a network or rendezvous claim is never accepted as that value.
- Existing LAN TLS, multicast/HTTP discovery, Android/Linux integrations, and the current app state/isolate boundaries are protected.
- Anywhere is online-to-online connectivity. There is no server inbox, stored file, offline delivery, or transfer history.

RA1 may define new boundaries and protocol requirements, but it does not authorize networking code, identity changes, accounts, UI, or LAN rewrites.

## 3. Primary-source research summary

The standards and current implementations support these conclusions:

1. **ICE is a traversal procedure, not a file transport.** RFC 8445 gathers host, server-reflexive, and relayed candidates, performs authenticated connectivity checks, nominates a pair, and defines ICE restart. STUN (RFC 8489) discovers a mapped address; it does not make that address reachable. TURN (RFC 8656) supplies a relayed candidate and supports IPv4/IPv6 plus UDP, TCP, TLS-over-TCP, and DTLS client-to-server transports.
2. **“Symmetric NAT” is too coarse.** RFC 4787 replaces cone/symmetric labels with mapping and filtering behavior. Address-and-port-dependent mappings can assign a different public port for each destination, so a STUN mapping learned against one server may not be usable by a peer. CGNAT is not automatically fatal, but multiple layers and restrictive mapping/filtering materially reduce direct success; relaying is the honest fallback.
3. **QUIC is a strong file substrate but needs fallback.** RFC 9000 provides multiplexed streams, per-stream flow control, connection IDs, and path validation/migration; RFC 9001 requires TLS 1.3. RFC 9308 explicitly says UDP can be blocked and applications must either fail or provide a fallback with the same security properties. QUIC migration does not create reachability on a new network and cannot begin before handshake confirmation.
4. **WebRTC DataChannels solve traversal but carry a larger, media-shaped stack.** RFC 8831 is SCTP over DTLS over ICE/UDP. It supports reliable and partially reliable messages, but it is message-oriented, does not use SCTP multihoming, and recommends message interleaving to stop large messages monopolizing the association. Relay needs native Rust byte streams and files, not browser/media interoperability.
5. **DERP is a packet router, not a trust authority.** Tailscale's source describes DERP as last-resort forwarding for already-encrypted WireGuard packets. The protocol uses bounded frames and outbound TLS connections, while the endpoints retain end-to-end security. That trust split fits Relay; Tailscale's account/control plane does not.
6. **libp2p is capable but wider than Relay needs.** Its DCUtR specification coordinates direct connection upgrade through an existing circuit relay, and rust-libp2p provides QUIC, relay, and DCUtR. Adopting its peer identity, multiaddr, secure-channel negotiation, swarm, relay reservation, and protocol stack would duplicate Relay identity and add a large maintenance surface.
7. **Iroh is the clearest current “F” candidate.** At pinned release 1.0.3 it exposes peer-to-peer QUIC streams, integrated hole punching, custom discovery, and a self-hostable Rust relay with its stock HTTP(S) upgrade transports, per-client rate limiting, and a 64 KiB relay packet ceiling. Its `EndpointId` is an Ed25519 public key. These are unusually close to Relay's connectivity requirements, but its EndpointId must remain a routing/path credential and its advertised success rates must not be adopted without Relay measurements.
8. **Android cannot be treated as an always-running Dart process.** Android 12+ restricts background foreground-service starts; Android 14 requires declared foreground-service types; Android 15 limits `dataSync` foreground services to six aggregate hours per 24 hours for target API 35+ and forbids starting them from `BOOT_COMPLETED`. Android 14+ user-initiated data-transfer jobs require visible user initiation and a notification. Doze/App Standby restrict background network access, and process death remains possible.

## 4. Options comparison

These options are not perfectly equivalent: ICE is traversal, QUIC/WebRTC are transports, and DERP is a relay. The comparison asks whether each could anchor the complete Relay Anywhere design.

| Dimension | A. ICE + STUN + TURN | B. Raw QUIC + rendezvous | C. WebRTC DataChannels | D. DERP-inspired | E. libp2p | F. Iroh 1.0.3 |
|---|---|---|---|---|---|---|
| Android / Linux | Available, but socket handoff to QUIC needs engineering | Strong Rust/Linux; Android NDK must be proven | Native stacks exist; Rust/mobile integration is substantial | Simple outbound client model on both | Rust supports both targets; mobile lifecycle remains ours | Rust-native; official project has Android CI/demos, but Relay build/device proof is required |
| NAT traversal | Standards-based candidate/check model | None by itself | Mature ICE behavior | Coordinates punching but is not itself a complete candidate engine | DCUtR/AutoNAT/relay | Integrated relay-observed addresses and simultaneous UDP punching |
| CGNAT / mobile | Direct sometimes; TURN reliably relays | Direct only when a usable mapping/path exists | TURN fallback is reliable | Relay fallback is reliable | Circuit relay fallback | Relay fallback; direct rate must be measured |
| Address-and-port-dependent (“symmetric”) NAT | Usually needs TURN | Usually fails without prediction/relay | Usually TURN | Relay | Circuit relay | Relay |
| IPv4 / IPv6 | Both specified | Both in QUIC implementation | ICE supports both | Relay reachability depends on deployment | Multiaddr supports both | Endpoint has v4/v6 direct addresses and relay |
| Hotel / enterprise firewall | TURN/TLS helps, though non-HTTP protocols may still be blocked | UDP QUIC may be blocked | TURN/TCP/TLS can work; proxies remain variable | Secure HTTP upgrade transports are stronger than direct UDP, though restrictive proxies remain variable | WebSocket/circuit relay possible but more stack | Stock iroh-relay HTTP(S) upgrade transport; direct unavailable when outbound UDP is blocked |
| Implementation complexity | High if integrating ICE sockets with QUIC; lower with WebRTC | Low transport complexity, missing hard traversal work | Highest protocol stack: SDP/JSEP, ICE, DTLS, SCTP, DataChannel | Moderate and narrowly controllable | High breadth and configuration | Lowest end-to-end connectivity complexity, but dependency/API risk |
| Rust maturity | `webrtc-ice` exists; integration must be validated | Quinn is mature pure Rust | `webrtc-rs` is active but its 0.20 line is a recent Sans-I/O rewrite | Straightforward custom Rust; Tailscale implementation is Go | rust-libp2p mature and broad | 1.0.3, Rust, active; newer than Quinn/libp2p |
| Flutter / Android burden | FRB plus native lifecycle and UDP socket ownership | FRB around Rust core | FRB plus WebRTC state machine or native libwebrtc | FRB around a small client | FRB around swarm/event model | FRB around Endpoint/Connection plus lifecycle; smallest candidate API |
| Battery / background | Keepalives and candidate refresh cost; platform policy still dominates | UDP NAT keepalives; platform policy dominates | ICE consent/keepalives plus stack timers | One long-lived relay socket/keepalive | Multiple behaviors can cost more | One endpoint/relay session; still cannot bypass Android limits |
| Large-file throughput | Depends on transport above ICE; TURN bandwidth is data path | Excellent QUIC streams direct | Good if chunked; SCTP message and interleaving concerns | Relay transport adds latency and may add outer-stream HOL, but is fallback | QUIC direct good; relay limits/policy vary | QUIC streams direct and relayed; stock relay throughput/caps need RA2A measurement |
| Backpressure | TURN forwards packets; application transport owns it | QUIC stream/connection flow control | SCTP congestion control; application must bound messages | Must implement bounded queues and slow-peer policy | Stream mux/transport provides it | QUIC flow control; relay queue bounds still require source audit/test |
| Connection migration | ICE restart; transport-dependent | QUIC migration/path validation | ICE restart, no SCTP multihoming | Can reconnect, not migrate application session alone | Transport redial/upgrade | Project documents multipath/path switching; verify on Android |
| Resumability | Application responsibility | Application responsibility | Application responsibility | Application responsibility | Application protocol responsibility | Application responsibility; no server storage |
| Security fit | TURN credentials are infrastructure admission, not peer identity | QUIC TLS can bind to Relay, but custom verifier work is needed | DTLS fingerprint is not automatically Relay trust | Excellent opaque-router split if inner Relay auth is mandatory | Would introduce/align another peer identity and secure channel | Strong encrypted substrate; use an inner Relay TLS/proof to keep existing trust authoritative |
| Self-hostability | STUN/TURN readily self-hosted | Rendezvous only; relay still missing | Signaling and TURN self-hostable | Small relay self-hostable | Relays/bootstrap can be self-hosted | `iroh-relay` is open-source and configurable |
| Infrastructure cost | STUN tiny; TURN carries every relayed byte | Tiny rendezvous until a relay is added | Signaling tiny; TURN dominates | Relay bandwidth dominates | Relay bandwidth dominates | Relay bandwidth dominates; rendezvous remains tiny |
| Maintenance | Multiple standards/services and difficult interop matrix | We would own traversal correctness | Large evolving stack unrelated to files | Small protocol, but we own all edge cases | Large dependency surface | Smaller Relay-owned surface, but upstream version/API/security tracking is mandatory |

### Decision on alternatives

- **A alone is rejected** because ICE does not deliver an application stream. A bespoke ICE-to-Quinn socket adapter is a valid fallback plan, but duplicating an integrated current implementation is not the best first proof.
- **B alone is rejected** because a rendezvous exchange plus QUIC dial is not sufficient under two NATs. It is retained as the direct transport inside the chosen design.
- **C is rejected as primary** because Relay does not need browsers or media, while SCTP/DTLS/ICE/SDP integration, message sizing, non-multihoming, and Android lifecycle add burden. It remains a future browser-interoperability option, not the native Android/Linux core.
- **D alone is rejected** because a relay supplies reachability but not an efficient direct file path. Its opaque-packet and outbound-HTTPS ideas are adopted.
- **E is rejected for RA2A** because its identity, swarm, negotiation, address, relay-reservation, and discovery layers are broader than Relay's two-known-peer problem. DCUtR remains useful design evidence.
- **F is selected for RA2A** because it combines the required B + D behaviors behind native QUIC streams and permits custom discovery/self-hosting. RA2A uses stock `iroh-relay` 1.0.3; no Relay-specific relay is implemented. Selection is conditional, pinned, and reversible through the provider boundary.

## 5. Chosen architecture

The architecture has four strict layers:

```text
Local discovery or capability rendezvous
                │  produces short-lived addressing only
                ▼
Anywhere path provider (RA2A: iroh 1.0.3 + stock iroh-relay 1.0.3)
  direct QUIC ↔ coordinated punching ↔ opaque packet relay
                │  produces an unauthorised bidirectional stream
                ▼
End-to-end Relay secure channel
  inner TLS + observed certificate + RelayIdentityProofV1
                │  produces AuthenticatedPeer { trusted RelayId, stream(s) }
                ▼
Transfer semantics
  requests, encrypted metadata, bounded chunks, progress, cancel, resume
```

The Iroh endpoint key is generated for an online availability session and is **not** displayed, trusted, or stored as a Relay product identity. Its EndpointId is only a routing/path credential for Iroh's relay/QUIC layer. RelayId remains the authoritative Relay product identity and trust key. The peer remains untrusted until the inner TLS channel completes the existing Relay proof and the returned RelayId exactly matches the local trusted-device record. RA2 and the initial Anywhere implementation **shall** run this inner Relay TLS plus `RelayIdentityProofV1` inside an Iroh QUIC bidirectional stream, deliberately preserving the already-audited authentication contract.

The default hosted system may operate rendezvous and relay together for simplicity, but they are separate logical roles, endpoints, credentials, scaling profiles, and trust statements.

## 6. Connectivity/path model

A future Relay-owned interface should describe capability, not vendor types:

```text
PresenceDirectory
  publish(descriptor, expiry)
  resolve(trustedPeer) -> short-lived descriptor

PathProvider
  connect(descriptor, cancellation) -> PendingTransport
  accept(cancellation) -> PendingTransport

PendingTransport
  pathKind: lan | internetDirect | relayFallback
  openBidirectionalStream()
  pathChanges()
  close()

RelaySecureChannel
  authenticate(stream, expectedRelayId) -> AuthenticatedSession

AuthenticatedSession
  peerRelayId
  pathKind/pathChanges (diagnostic only)
  transfer streams/control
```

`pathKind` must never influence trust policy. A direct connection with the wrong RelayId fails; a relayed connection with the correct proof may succeed. UI may show “Direct” or “Relayed” without implying different encryption.

Expected path behavior:

| Network case | Expected result |
|---|---|
| Same LAN | Existing multicast/HTTP path wins; no rendezvous wait and no Iroh LAN replacement |
| Public IPv6 on both sides | Race global IPv6 direct first; still validate firewall reachability and Relay identity |
| One device behind NAT | Public side plus simultaneous UDP normally permits direct; otherwise relay |
| Both behind endpoint-independent NATs | Coordinated UDP hole punching is likely, not guaranteed |
| CGNAT | Punching can work when mapping/filtering permits; otherwise relay, especially with nested NAT |
| Address-and-port-dependent NAT on either/both | Do not predict success; relay is the normal outcome |
| Restrictive hotel/enterprise network | If UDP works, direct may work; otherwise try the secure relay upgrade transports supplied by stock Iroh, subject to proxy/network policy |
| Android cellular ↔ Linux home | Try v6 and punched v4; expect relay on restrictive carriers/home NAT combinations |
| Wi-Fi ↔ cellular change | QUIC path validation/multipath first; if unreachable, retain/rebuild relay path, re-rendezvous, re-authenticate, then application-resume |

## 7. Transport choice

### Near term

- Preserve HTTP/TLS for LAN.
- Use QUIC as the primary Anywhere transport, initially through pinned Iroh.
- Open one reliable bidirectional QUIC stream for the mandatory inner Relay TLS/authentication and initial RA2A byte test.
- In a later transfer protocol, use separate QUIC streams for control and bounded file ranges so one lost stream does not head-of-line block unrelated files. Let QUIC flow control provide backpressure; cap application buffers independently.
- Disable application actions in QUIC 0-RTT initially. RFC 9308 notes replay risk; pairing, authorisation, transfer acceptance, and writes are not safe early data.

### Why inner TLS instead of changing the proof

The current proof is specifically bound to a TLS certificate fingerprint. Replacing that field with an Iroh EndpointId, QUIC exporter, or rendezvous key in RA2 would create a new primitive and a second validation path. Running rustls end-to-end over a QUIC stream preserves the exact model: each endpoint observes the peer's inner certificate, challenges it with a single-use nonce, verifies `RelayIdentityProofV1`, and compares the resulting RelayId to trust storage. The outer Iroh QUIC encryption protects path-control and application packets across direct and relayed paths; the inner Relay TLS/proof remains the authoritative product trust boundary.

This is not “TCP over QUIC”: TLS records add confidentiality/authentication but no retransmission or congestion-control loop. The QUIC stream owns reliability and flow control. RA2A must still measure overhead and prove clean shutdown/backpressure.

Nested TLS is a **V1 compatibility and security-preservation strategy**, not a frozen permanent architecture decision. A future phase may research a new Relay proof bound directly to the authenticated QUIC connection or a channel exporter, but only after Anywhere interoperability and security evidence exists. That work is explicitly outside RA2, must not modify `RelayIdentityProofV1`, and must not weaken or silently negotiate away the inner TLS contract used by the initial Anywhere implementation.

### Longer term

Do not converge LAN and Anywhere during RA1/RA2. After production evidence, Relay may define one `AuthenticatedSession` transfer protocol with:

- an adapter over existing LAN HTTP/TLS, and
- a native multi-stream QUIC implementation for Anywhere.

Only then should convergence be evaluated. Rewriting LAN HTTP/TLS merely for conceptual symmetry is rejected.

## 8. Identity/authentication integration

Three concepts remain separate:

| Concept | Authoritative material | Meaning |
|---|---|---|
| Identity | Persistent Relay Ed25519 public key and derived RelayId | Who cryptographically controls this device identity? |
| Discovery/addressability | Per-peer directory capability and short-lived endpoint descriptor | Where can an online instance currently be attempted? |
| Authorization | Local trusted-device record and per-action receive policy | Is this identity allowed to connect or send this content now? |

Rules:

1. Pairing stores the peer's Relay public key/RelayId in the existing secure/local trust domain. A directory token, Iroh EndpointId, relay credential, or invitation code is never stored as peer identity.
2. Each new transport, including after migration/reconnect, performs fresh inner TLS and fresh single-use proof. Compare the result with the explicitly selected trusted peer using constant-time digest comparison where applicable.
3. Any malformed proof, role mismatch, reused/expired challenge, certificate mismatch, unexpected RelayId, identity reset, or unsupported required auth version closes every candidate path. There is no “try an unverified fallback.”
4. The inner TLS endpoint certificate is generated/owned exactly as the current Relay transport requires. Its fingerprint comes from the installed/observed DER certificate, never from the rendezvous descriptor.
5. The ephemeral Iroh endpoint key may change every online session. Its EndpointId is a routing/path credential analogous to a QUIC connection identity, not a Relay product identity. RelayId alone remains authoritative for product identity/trust. Do not derive the Iroh key from or export the Relay private key.
6. A malicious directory can delete, delay, replay, or substitute an endpoint descriptor. TTL/sequence checks limit replay; substitution can cause DoS, but the substituted endpoint cannot pass the expected Relay proof.

## 9. Device-linking model

The initial no-account model is explicit trusted-device registration.

### Recommended pairing transcript

1. Device A creates a random, single-use 256-bit invitation secret, invitation ID, expiry (for example ten minutes), supported protocol version, A's Relay public key/RelayId, and configured rendezvous/relay hints.
2. Prefer a QR code shown by A and scanned by B. An invitation URI is the same payload for an authenticated user-chosen channel. A short typed code is only a lookup/PAKE input and must not be a bearer authenticator.
3. B redeems once, sends its Relay public key and a fresh response nonce through the invitation mailbox, and both sides display a short authentication string derived from the complete pairing transcript. The user confirms on both devices unless the product can prove the QR channel bound both directions.
4. Each device stores an explicit trust record: peer Relay public key/RelayId, user label, allowed capabilities, and **distinct directional directory secrets**. The one-time invitation is erased.
5. Future address lookup uses directory capabilities; future connections authenticate with Relay proof. Possession of any directory/invitation material alone never authorizes a file.

### Evaluation

- **QR:** best default for co-located devices; high-entropy payload and clear user intent.
- **Invitation URI:** acceptable through an already-authenticated channel, with expiry, one-time consumption, and confirmation; link theft can race redemption.
- **One-time human code:** usable only with aggressive rate limiting and a PAKE or explicit SAS confirmation. A six-digit bearer code is insufficient.
- **Rendezvous token:** addressability/admission capability only, never identity.
- **Device directory secret:** good for unenumerable bilateral slots; rotate/revoke per trusted peer.
- **Self-hosted rendezvous:** changes availability/privacy operator, not peer trust.

Identity reset is a new identity. The UI must mark the old trusted record unavailable/revoked and require new pairing; it must never silently replace the key from a directory response.

## 10. Rendezvous service

### RA2A rendezvous boundary

RA2A does **not** implement the production directory design below. It uses one memory-only process and one unguessable temporary capability to exchange only the minimum Iroh `EndpointAddr` information required by the two test endpoints. Each record has a short TTL and is deleted on retrieval, explicit cleanup, or expiry. There is no database, account, global RelayId directory, production contact graph, padding scheme, encrypted-directory protocol, invitation ceremony, or durable state. Stopping the process loses all records by design.

The production privacy and directory model remains an RA1 concept for later design. It is deferred until RA2A and RA2B validate that the selected path architecture works; it must not become accidental proof infrastructure.

### Smallest useful API

Use opaque, bilateral, directional mailboxes rather than a global RelayId directory:

```text
PUT /v1/presence/{opaque-slot}
  fixed/padded encrypted descriptor, expiry, sequence
  request MAC or write capability

GET /v1/presence/{opaque-slot}
  read capability
  -> descriptor or offline

POST /v1/invitations/{random-id}/redeem
  one-time bounded pairing payload
```

The encrypted descriptor contains only:

- protocol version and feature bits;
- random boot/session ID and monotonic sequence;
- ephemeral transport EndpointId;
- one or more permitted relay URLs and current short-lived connection hints;
- issued-at/expiry (target presence TTL: 60–120 seconds, refreshed while online).

Do not include device name, filename, file size, history, or the persistent RelayId in the outer record. Pad descriptors to a small set of sizes. A per-peer slot means one device with N trusted peers publishes N encrypted copies; that is an intentional control-plane cost that reduces trivial global contact-graph enumeration. It does not prevent IP/timing correlation, and the document makes no anonymity claim.

### Authentication and state

- Registration authentication is a high-entropy write capability or MAC over method, slot, ciphertext hash, expiry, and sequence. This proves authority to update that slot; it is not peer authentication.
- Read and write capabilities are distinct. The server stores only salted capability verifiers if it must validate bearer material.
- Presence and relay mappings are memory/TTL-store state. Expire without refresh; reject decreasing sequence numbers and excessive future expiry.
- Persist only what atomic one-time invitation consumption, revocation, and abuse quotas require. Never persist transfer history or application data.
- Invitation redemption is limited by invitation, source network, device, and global budgets; fixed responses avoid token enumeration. Repeated failures consume the invitation budget.
- Multiple rendezvous servers are allowed. A trust link can carry an ordered set of URLs and independent slots. Publish to configured servers; resolve in parallel; deduplicate by signed/encrypted session sequence. Server disagreement affects availability only.
- Default infrastructure should offer TLS and stable operations. Self-hosted endpoints use normal Web PKI or an explicitly pinned administrator certificate for service authentication, but service TLS never substitutes for Relay peer proof.

Accounts are not necessary for two already-trusted devices. They may later improve recovery, multi-device administration, push delivery, and abuse billing, but must remain an outer control-plane authorization system; compromise must not let the account service impersonate a RelayId.

## 11. NAT traversal

RA2A should use Iroh's coordinated traversal, while Relay's required behavior remains provider-neutral:

1. Gather local IPv4/IPv6 addresses and relay-observed/reflexive addresses from the same UDP endpoint that will carry QUIC.
2. Exchange candidates/hints only inside the encrypted rendezvous/relay coordination path.
3. Prefer reachable global IPv6, then direct IPv4/IPv6 candidate pairs, using a Happy-Eyeballs-style small stagger rather than serial multi-second waits.
4. Both endpoints send authenticated QUIC/path-probe traffic simultaneously from the eventual transport socket. A STUN result from a different socket or destination is not assumed reusable.
5. Keep the stock Iroh relay connection available during the attempt. If direct succeeds, stop sending application data through relay; retain a low-rate control path only when justified by lifecycle/battery measurements.
6. Restart gathering on network change. QUIC migration is attempted first, but failed path validation triggers fresh rendezvous and authentication.

STUN may be configured independently for a future provider, but **raw UDP hole punching based on one STUN mapping is not an ICE equivalent**. Under address-and-port-dependent mapping, the peer-facing mapping can differ from the STUN-facing mapping. Port prediction is not a security or reliability strategy. TURN is standards-correct when a generic ICE deployment needs a relayed UDP candidate, but the chosen Iroh provider already supplies an integrated packet relay; operating both TURN and Iroh relay in RA2A would duplicate the expensive path without proving the selected architecture.

## 12. Direct connection strategy

Direct candidates race without delaying LAN:

- At user selection, consult the already-populated LAN discovery store immediately. If the selected trusted RelayId is locally reachable, use the current LAN path.
- In parallel, resolve remote presence with a two-second control-plane deadline. Directory failure does not affect LAN.
- Establish the relay coordination connection and start IPv6/direct punched QUIC attempts. Start the best candidate immediately and stagger the next family/path by approximately 200 ms; do not serialize all candidates.
- Reserve an initial **four-second direct-preference budget** after candidates are available. If no direct path has completed inner Relay auth, permit relay data. Continue a bounded direct-upgrade attempt for up to ten seconds total if the provider can migrate the same QUIC connection without restarting the authenticated inner stream.
- If the network reports UDP prohibited/unreachable, skip the remaining direct delay and use the stock Iroh relay path immediately.
- First authenticated path wins. Cancel losing handshakes and release sockets. These values are RA2A starting parameters, not production constants; record histograms and tune without logging peer identifiers.

Public IPv6 is preferred but not trusted more: host firewalls can still block unsolicited traffic, privacy addresses rotate, and the Relay proof remains mandatory.

## 13. Relay fallback

### Choice

RA2A shall use the **stock, self-hosted `iroh-relay` 1.0.3 implementation** as its fallback path. Do not implement or fork a custom DERP-derived Relay fallback for the proof. Use the secure relay transports and negotiation behavior supplied by pinned Iroh 1.0.3 rather than describing the current transport as simply “WebSocket.” Relay application content remains encrypted inside Iroh QUIC, and the mandatory inner Relay TLS plus `RelayIdentityProofV1` remains end-to-end across the relayed path. `iroh-relay` must never terminate the inner Relay TLS channel.

A custom Relay-specific fallback server is deferred. It may be researched only if RA2A/RA2B and later operational testing show that stock `iroh-relay` is inadequate for restrictive-network reachability, admission control, scaling, operational support, or cost. Such evidence would reopen the relay decision; it would not authorize weakening the existing Relay trust contract.

### TURN versus custom byte relay versus DERP-like framing

| Choice | Fit |
|---|---|
| TURN | Best interoperable ICE relay and useful if Relay later owns a standards ICE provider. It relays addresses/packets, supports v4/v6 and several client-server transports, but adds allocations, permissions, credentials, and a protocol that Relay otherwise does not need. TURN credentials authenticate service use, never the peer. |
| Custom byte-stream relay | Easy conceptual match for two outbound streams and inner TLS, but would require Relay to design framing, pairing, fairness, reconnect, proxies, observability, and every abuse boundary. It also cannot transparently preserve a QUIC connection unless it transports QUIC datagrams. |
| DERP-like packet relay | Best chosen fit: small bounded destination-addressed frames, secure HTTP upgrade transport, no arbitrary Internet egress, and encrypted QUIC remains end-to-end. RA2A uses Iroh's stock Rust implementation rather than recreating this model. |

### Required relay properties

- Forward only opaque frames between currently connected endpoint IDs; no disk spool, cache, inbox, filename, MIME type, or application metadata.
- Endpoint IDs are ephemeral online-session routing keys. Relay login proves possession of that transport key; it does not establish Relay trust.
- Use the pinned implementation's 64 KiB maximum frame. Verify its handshake, connection, idle, and pairing timeouts rather than changing the relay protocol during RA2A.
- Use bounded per-client and per-destination queues. Await downstream capacity; on a slow receiver, apply fair scheduling then drop/close rather than accumulate unbounded memory. Verify these properties in source and stress tests—do not infer them merely from QUIC flow control.
- Rate-limit bytes/sec, burst, concurrent connections, frames/sec, failed destinations, and new handshakes per access capability and source network. Cap unauthenticated input below any response size to prevent amplification.
- Destination must be online and explicitly addressable; no generic proxy or UDP egress. Unknown destinations get a constant-size failure or silent drop.
- Account bandwidth against an opaque relay access capability where possible, not RelayId. Rendezvous may mint short-lived relay admission credentials; possession permits bandwidth only and cannot impersonate a peer.
- Cancellation closes the relevant QUIC/application streams and stops forwarding promptly. Idle and half-open sessions expire.
- Reconnect never resumes at the relay. Endpoints re-rendezvous, establish a new path, perform fresh Relay authentication, and resume from locally persisted transfer acknowledgements/content hashes.
- Self-hosting uses the unmodified pinned `iroh-relay` wire protocol and transport behavior. A malicious/self-hosted relay can drop, delay, reorder, correlate, or throttle; it still cannot forge inner TLS/proof or decrypt application data.

## 14. Android lifecycle

The honest first product lifecycle is **available while the app is active, or during a user-visible, explicitly started availability/transfer session**. A Dart isolate is not a service-lifecycle guarantee.

1. Rust networking is owned by an Android service/process component with explicit start/stop and state restoration, surfaced to Flutter through FRB. Flutter UI/isolate death must not silently imply successful transfer.
2. A user-started outgoing transfer on Android 14+ should evaluate a User-Initiated Data Transfer job for long transfers. It must be scheduled from a permitted visible state, show an ongoing progress/cancel notification, persist acknowledgements before reporting progress, and handle `onStopJob` plus process death. Older versions need a correctly typed foreground service fallback.
3. `dataSync` is the semantically closest foreground-service type for Internet file transfer, but target API 35+ limits aggregate runtime to six hours per 24 hours and forbids launch from `BOOT_COMPLETED`. `connectedDevice` is documented for local connections and is not a blanket justification for remote Internet availability. Do not misuse `remoteMessaging` or `specialUse` without policy review.
4. Background incoming offers cannot be guaranteed in RA1 without a permitted wakeup channel. If the app/availability service is not running, rendezvous presence expires and senders see the device offline. A later phase may evaluate FCM or another push provider using opaque per-device wake capabilities, but push possession still would not authenticate a Relay peer and high-priority delivery/FGS exemptions are conditional.
5. While a user-visible availability service is running, maintain the rendezvous/relay session with an ongoing notification and user stop action. Android 13+ notification permission affects drawer visibility; the service still must post its notification. Doze behavior must be tested, not assumed away.
6. Use `ConnectivityManager.NetworkCallback` to report default-network loss/change to Rust. Attempt QUIC path validation/migration, then relay/re-rendezvous. Wi-Fi-to-cellular continuity is a test criterion, not a promise.
7. No automatic boot startup in RA2B. Later boot recovery cannot start an Android 15 `dataSync` service; it may only restore paused state and invite explicit user action through permitted scheduling/notification mechanisms.
8. Incoming transfer prompts are shown only after Relay identity authentication. Notification text should avoid filename/size on the lock screen by default. Acceptance remains a separate authorization action.

## 15. Threat model

| Threat | Required response |
|---|---|
| Malicious rendezvous | Can observe timing/IP, return stale/substituted data, or deny service. Encrypted capabilities minimize content; TTL/sequence rejects stale data; inner Relay proof rejects substitution. |
| Malicious relay | Can observe endpoints/timing/volume and drop/delay/reorder. Outer QUIC and inner Relay TLS protect content/integrity; fresh proof prevents impersonation. |
| Malicious STUN/TURN | Can lie about mapped addresses or route/drop packets. Treat candidates as hints; peer auth is independent. TURN credentials grant service use only. |
| Stolen invitation | Short expiry, atomic one-time redemption, rate limits, transcript SAS, user confirmation, and revocation. A redeemed token alone is not trusted identity. |
| Replayed invitation/presence | Atomic consumed flag; boot ID, increasing sequence, expiry, and locally recorded trust transcript. |
| Peer impersonation / MITM | Exact expected RelayId plus proof bound to the observed inner TLS certificate. Any mismatch fails closed across every path. |
| Downgrade to unverified path | AuthenticatedSession is the only transfer API. No LAN/relay/legacy exception after a trusted peer was selected. No unsafe QUIC 0-RTT actions. |
| Identity key reset/change | Treat as new device; explicit warning and re-pair. Never update trust from rendezvous/account data. |
| Stale registration | Short TTL, refresh, session ID, monotonic sequence, no offline queue. |
| Metadata leakage | Opaque per-peer slots, encrypted padded descriptors, ephemeral transport IDs, minimal logs/retention; acknowledge remaining IP/timing/volume correlation. |
| Device enumeration | 256-bit unguessable slots, uniform not-found responses, no public RelayId lookup, rate limits. |
| DoS | Small pre-auth state, strict sizes/timeouts, proof before transfer allocation/prompt, per-source/capability quotas, cancellation, global circuit breakers. |
| Bandwidth abuse | Short-lived admission capabilities, byte/burst/concurrency quotas, optional user/self-host quotas, no arbitrary egress. |
| Relay amplification | Do not send more pre-auth bytes than received; destination must be connected; cap errors and fan-out; one sender/one destination per frame. |
| Compromised trusted peer | Cryptography cannot help. Preserve receive prompt, path sanitization, disk limits, file-count/size limits, cancel, and explicit trust revocation. |
| Future account compromise | Account can alter discovery/availability but cannot sign Relay proof or replace a trusted key without local confirmation. |
| Malicious file sender | Keep current filename/path validation, SAF boundaries, available-space checks, bounded decompression/metadata, no executable auto-open, and per-file integrity. |

The security invariant is:

```text
route established
AND inner TLS certificate observed locally
AND fresh Relay proof is cryptographically valid
AND proved RelayId equals the selected trusted-device record
AND the local receive/share policy authorizes this action
```

If any term is false or unknown, transfer does not start.

## 16. Privacy/metadata

Relay Anywhere is confidential transport, not anonymity.

| Observer | Can observe | Must not receive |
|---|---|---|
| Rendezvous | Client IP, timing, opaque slot, padded descriptor size, TTL, request rate; can correlate slots by source/timing | RelayId, device name, filenames, file sizes, peer-readable endpoint details, transfer history |
| Fallback relay | Source/destination transport EndpointIds, client IPs, connection times, packet/byte volumes, relay region | Relay identity where avoidable, filenames, MIME, messages, file plaintext, inner TLS keys |
| STUN/TURN (if configured) | Source IP, mapped/relayed address, timing, volume; TURN sees destination addresses and relayed packet sizes | Application plaintext or authority over Relay identity |
| ISP/network operator | Service IPs/DNS/SNI where visible, timing, UDP/TCP characteristics, volumes; direct paths reveal peer IPs to each peer/network | TLS/QUIC/inner application plaintext |
| Remote peer | Authenticated Relay identity, necessary device presentation, offered file metadata after policy permits, sender IP on direct path | Unselected local files, unrelated trust graph/history, directory secrets |

Direct P2P necessarily reveals peer IP addresses to the other peer. Relay hides peer IPs from each other only if endpoint descriptors and side channels do not expose them, while revealing both IPs to relay infrastructure. Logs should use short-lived random correlation IDs; operational metrics aggregate path type, latency, failure class, and byte totals without RelayId.

## 17. Infrastructure/cost implications

Cost splits cleanly:

- **Rendezvous:** small encrypted presence records, refreshes, and invitation transactions. CPU/storage/egress are tiny; abuse protection and availability engineering dominate.
- **STUN:** a few binding/check packets per path attempt. Bandwidth is small. It may be unnecessary with the selected provider's relay-observed addressing.
- **Relay/TURN:** carries the complete data plane for every relayed transfer. Required capacity is approximately relayed transfer bytes times the provider's ingress/egress accounting, plus protocol overhead and regional replication/failover. Therefore the relay fallback percentage, average file size, concurrency, and regional distance dominate cost—not the number of registered devices.

Do not quote a provider price before choosing region/provider and measuring traffic. Instrument direct-versus-relayed bytes, not merely connection count. Multi-region relays improve latency and failure isolation but add deployment, certificate, steering, monitoring, and version-rollout burden.

Rust is a good fit for both services because Relay already has Rust expertise, the transport provider and relay are Rust, async bounded I/O is natural, and one language simplifies protocol types and fuzz/property tests. RA2A rendezvous is strictly memory-only. A later production rendezvous could use Axum plus a TTL store, with durable storage only if atomic invitation consumption and abuse quotas demonstrably require it. The fallback relay begins with unmodified, pinned `iroh-relay` 1.0.3, not a new protocol; deployment must pin versions, expose health/metrics separately, and disable application-data logging.

## 18. Existing LAN integration

Exactly unchanged:

- `packages/core` current HTTP server/client routes, TLS behavior, transfer code, multicast, and v2 discovery;
- the Relay Ed25519 identity type, RelayId derivation, `RelayIdentityProofV1`, signer ownership, and secure storage;
- current Android/Linux LAN discovery and Android ↔ Linux transfer behavior;
- app transfer UI, file selection/save target logic, progress, and cancel for LAN.

Smallest future additions, none implemented in RA1:

```text
packages/core/src/anywhere/
  presence/          # provider-neutral encrypted descriptors/capabilities
  path/              # PathProvider and path events
  secure_channel/    # inner TLS adapter + existing proof orchestration
  session/           # authenticated stream/session boundary

server/ or a separate workspace service
  rendezvous/        # tiny TTL control plane
  relay deployment   # pinned iroh-relay configuration, not app logic

packages/localsend_isolates/
  future FRB tasks/events for lifecycle and path state only

app/
  future trusted-device/addressability state and Android service integration
```

The exact locations are proposals. Keep `lib/src/task/` pure and route networking through the established Rust/isolate architecture. LAN can later be adapted to an `AuthenticatedSession`, but it must not depend on rendezvous, Iroh, STUN, TURN, or Internet availability.

## 19. Failure/fallback state machine

```text
IDLE
  └─ user selects known trusted RelayId
       ├─ start LAN lookup immediately
       └─ query remote presence concurrently (2 s deadline)

CANDIDATES
  ├─ LAN candidate available -> existing LAN TLS/proof
  └─ remote descriptor -> establish relay coordination + race direct QUIC
                         (best immediately, next path/family ~200 ms later)

AUTHENTICATING(path)
  ├─ inner TLS + fresh proof returns expected RelayId -> CONNECTED(path)
  ├─ identity/proof mismatch -> SECURITY_FAILURE; cancel every path; no fallback
  ├─ path fails and another candidate remains -> AUTHENTICATING(next)
  └─ no direct by 4 s / UDP blocked -> AUTHENTICATING(relay)

CONNECTED(direct or relay)
  ├─ direct upgrade succeeds within bounded 10 s window -> migrate; retain auth
  ├─ user cancel -> send cancel, close streams, discard pending state
  ├─ network change -> RECOVERING
  └─ transfer complete -> close/idle according to availability policy

RECOVERING
  ├─ QUIC validates a new path within ~3 s -> CONNECTED
  └─ otherwise re-resolve/reconnect within 15 s, perform fresh Relay auth,
     resume from locally acknowledged ranges -> CONNECTED
  └─ deadline/offline -> PAUSED/FAILED with explicit user-visible reason
```

Additional rules:

- Cancellation tokens flow through directory query, candidate gathering, handshakes, auth, and transfer tasks. Losing racers must not leak background sockets.
- Directory timeout with a LAN candidate does not delay LAN. Directory/relay failure reports “remote path unavailable,” not “peer untrusted.”
- Relay auth failure and RelayId mismatch are security failures, distinct from timeout/offline. Never retry them through another provider without new user action and diagnostics.
- Resume is application-level: locally persist transfer ID, authenticated peer RelayId, immutable manifest digest, per-file/range acknowledgements, and integrity hashes. After reconnect, re-authenticate first and require the same RelayId and manifest. The relay stores nothing.
- Initial timing values are hypotheses: RA2A covers Linux/network behavior, while RA2B adds physical mobile, UDP-blocked Wi-Fi, and Wi-Fi/cellular observations before production tuning.

## 20. Self-hosting

Expose an advanced infrastructure profile containing:

- one or more rendezvous HTTPS URLs;
- zero or more STUN URLs for a future ICE/plain-QUIC provider;
- zero or more TURN URLs plus short-lived credentials only when that provider is enabled;
- one or more Iroh/Relay fallback URLs and optional admission credentials.

Changing these changes who observes metadata and who can deny service; it does **not** change trusted Relay identities. Configuration should validate the secure HTTP(S) relay upgrade transports supported by pinned Iroh, reject plaintext outside explicit local development, support normal Web PKI plus deliberate certificate pinning, and show which operator is used. Peers may use different rendezvous servers if pairing carries mutually reachable slots; relay selection needs at least one common/reachable relay or an interoperable bridge.

Default infrastructure should be conservative and version-pinned. Community servers can coexist, but clients must not accept a server-provided peer key or downgrade authentication. Misconfigured STUN/TURN/relay can only cause failed/slower paths when the inner security invariant is enforced.

## 21. RA2 proof scope

RA2 is split into two gated, disposable connectivity proofs. Neither is product networking.

### Dependency and toolchain pin

- RA2A must declare `iroh = "=1.0.3"` and use the matching stock/self-hosted `iroh-relay` 1.0.3 implementation.
- The RA2 proof's resolved `Cargo.lock` must remain committed so the exact dependency graph is reproducible.
- Iroh 1.0.3 requires Rust 1.91. Relay's pinned Rust 1.97.1 satisfies that requirement.
- RA1 adds no dependency; these pins apply only when RA2A is implemented.

### RA2A — Linux/network proof

Build exactly:

- two ephemeral Iroh EndpointIds, used only as routing/path credentials;
- two generated/restored existing Relay identities, whose RelayIds remain authoritative;
- one memory-only capability rendezvous that exchanges the minimum required Iroh endpoint address information, with an unguessable temporary capability, short TTL, deletion, and no database;
- a direct Iroh QUIC attempt with actual selected-path reporting;
- a forced fallback through stock/self-hosted pinned `iroh-relay` 1.0.3 by blocking the direct path;
- one existing Relay TLS channel inside an Iroh QUIC bidirectional stream;
- a fresh `RelayIdentityProofV1` verified against the expected RelayId on every new authenticated connection;
- a 1 MiB random stream in bounded chunks, receiver SHA-256 comparison, cancellation, slow-receiver/backpressure observation, and clean close;
- identity substitution, RelayId mismatch, wrong inner certificate fingerprint, replayed challenge, and changed-proof-byte negative tests.

RA2A has no Flutter UI, production file transfer, Android integration, production directory protocol, accounts, or offline delivery.

RA2A succeeds only if:

1. The direct run reports the actual Internet-direct path, both sides prove the expected RelayId, and the 1 MiB SHA-256 matches.
2. With direct connectivity intentionally blocked, the same test reports the stock Iroh relay path, proves the same RelayIds through inner Relay TLS, and produces the same hash. Relay observation/logging contains no application plaintext, RelayId, filename, or device name.
3. Every substitution, mismatch, certificate-binding, challenge-replay, and proof-corruption test fails closed before accepting test bytes, with no unverified fallback.
4. Cancellation stops both endpoints promptly, and bounded-memory/backpressure observations reveal no unbounded growth under a slow receiver.
5. The temporary rendezvous record expires or deletes correctly; stopping rendezvous after endpoint exchange does not break an established path.
6. Existing LAN discovery/transfer code is not invoked, modified, or replaced.

RA2A fails if the pinned Iroh dependency is not reproducible, the selected path cannot be reported, inner Relay TLS/proof requires changing `RelayIdentityProofV1`, identity mismatch reaches a usable session, stock `iroh-relay` exposes application plaintext, or its observed buffering/admission behavior makes even a proof unsafe. Failure stops RA2B and returns the transport decision for review; it does not authorize a custom relay automatically.

### RA2B — Android/Linux physical proof

RA2B starts only after every RA2A criterion passes. It integrates the same pinned Iroh path into Relay's existing Rust Android build and proves, without adding production file UI:

- one physical Android device and one Linux device on different networks;
- a direct connection attempt with actual path reporting;
- a deliberately forced stock `iroh-relay` fallback;
- the same inner Relay TLS and fresh `RelayIdentityProofV1` authentication on both paths;
- foreground/background lifecycle observations appropriate to the proof harness, including process/service behavior and user-visible lifetime where required;
- Wi-Fi-to-cellular or cellular-to-Wi-Fi transition where practical, recording whether Iroh migrates the path or Relay must reconnect, re-authenticate, and resume.

RA2B succeeds only if direct and forced-relay runs preserve the expected RelayId and byte integrity on physical devices, Android lifecycle behavior is reported rather than assumed, and a practical network transition either remains connected or fails into an explicit recoverable state without weakening authentication. A platform build failure, silent process/lifecycle loss, inability to force/report the relay path, or any authentication downgrade places Anywhere on hold.

## 22. Explicit non-goals

- No production file transfer or UI.
- No change to LAN discovery, LAN HTTP/TLS, current transfers, or security primitives.
- No accounts, usernames, email/phone identity, social graph, or account recovery.
- No offline delivery, permanent inbox, cloud storage, server-readable cache, or server transfer history.
- No automatic startup, boot receiver, always-on promise, push service, or battery-optimization exemption request.
- No browser client, WebRTC interop, VPN, mesh routing, arbitrary proxy, DHT, pubsub, or multi-hop community network.
- No exact cloud pricing or unmeasured direct-connect success claim.
- No production dependency adoption merely because RA1 selected an RA2 candidate.

## 23. Risks/open questions

1. **Iroh dependency age/change:** 1.0.3 is current and promising but comparatively new. Pin exact source, audit advisories/license/transitives, and define an upgrade policy.
2. **Relay queue guarantees:** the source proves a 64 KiB frame ceiling and offers rate-limit configuration, but RA2A must trace every queue and test slow consumers before claiming bounded memory.
3. **Ephemeral EndpointId support:** confirm frequent endpoint-key rotation does not harm relay selection, migration, or reconnect and that no default discovery publishes it unexpectedly.
4. **Inner TLS integration:** prove rustls over the selected bidirectional stream, mutual certificate observation, both proof roles, cancellation, and no private-key export outside the existing Rust signer boundary.
5. **Path semantics:** verify a relayed connection can upgrade to direct without disrupting the inner stream; otherwise freeze the chosen path per authenticated session and reconnect/resume explicitly.
6. **Android socket migration:** confirm the Rust endpoint responds correctly to Android default-network changes and carrier NAT rebinding on physical devices.
7. **Restrictive proxies:** Iroh's stock secure HTTP(S) relay upgrade transports are more deployable than direct UDP, not universal. RA2B should observe authenticated HTTP proxies, TLS interception, captive portals, and UDP blocking where practical.
8. **Directory privacy:** per-peer opaque slots reduce enumeration but source IP/timing can still reveal a contact graph. Evaluate batching, jitter, retention, and optional privacy proxy only after baseline measurements.
9. **Invitation UX:** specify the transcript/SAS and safe remote pairing ceremony with a cryptographic review; do not invent a low-entropy bearer-code protocol.
10. **Resume protocol:** current LAN transfer is not to be changed. A later Anywhere protocol needs immutable manifests, local acknowledgement durability, and per-range integrity without becoming cloud storage.
11. **Relay admission:** after RA2, decide how default infrastructure issues short-lived bandwidth capabilities without accounts while resisting token sharing. RA2A only evaluates the admission and rate-limit controls already present in pinned stock `iroh-relay`.
12. **Licensing/upstream policy:** review pinned Iroh/noq/relay licenses, support expectations, and forkability before depending on public protocol compatibility.

## 24. Exact primary sources examined

All technical decisions above use primary standards, official platform documentation, or official project specification/source. Accessed 2026-08-18.

### IETF and W3C

- [RFC 8445 — Interactive Connectivity Establishment (ICE)](https://www.rfc-editor.org/rfc/rfc8445.html)
- [RFC 8489 — Session Traversal Utilities for NAT (STUN)](https://www.rfc-editor.org/rfc/rfc8489.html)
- [RFC 8656 — Traversal Using Relays around NAT (TURN)](https://www.rfc-editor.org/rfc/rfc8656.html)
- [RFC 4787 — NAT Behavioral Requirements for Unicast UDP](https://www.rfc-editor.org/rfc/rfc4787.html)
- [RFC 7857 — Updates to NAT Behavioral Requirements](https://www.rfc-editor.org/rfc/rfc7857.html)
- [RFC 8305 — Happy Eyeballs Version 2](https://www.rfc-editor.org/rfc/rfc8305.html)
- [RFC 9000 — QUIC: A UDP-Based Multiplexed and Secure Transport](https://www.rfc-editor.org/rfc/rfc9000.html)
- [RFC 9001 — Using TLS to Secure QUIC](https://www.rfc-editor.org/rfc/rfc9001.html)
- [RFC 9308 — Applicability of the QUIC Transport Protocol](https://www.rfc-editor.org/rfc/rfc9308.html)
- [RFC 8831 — WebRTC Data Channels](https://www.rfc-editor.org/rfc/rfc8831.html)
- [RFC 8832 — WebRTC Data Channel Establishment Protocol](https://www.rfc-editor.org/rfc/rfc8832.html)
- [W3C WebRTC: Real-Time Communication in Browsers](https://www.w3.org/TR/webrtc/)

### Official implementations and specifications

- [Iroh 1.0.3 crate documentation](https://docs.rs/iroh/1.0.3/iroh/) and [Iroh endpoint model](https://docs.iroh.computer/concepts/endpoints)
- [Iroh NAT traversal](https://docs.iroh.computer/concepts/nat-traversal), [relay model](https://docs.iroh.computer/concepts/relays), [custom relay deployment](https://docs.iroh.computer/connecting/custom-relays), and [QUIC model](https://docs.iroh.computer/protocols/using-quic)
- [Iroh repository tag v1.0.3](https://github.com/n0-computer/iroh/tree/v1.0.3), peeled commit `f2eb930dda3779c6d852b72f3712aacd6e573ab1`; specifically `iroh-base/src/key.rs`, `iroh-relay/src/protos/handshake.rs`, `iroh-relay/src/protos/relay.rs`, `iroh-relay/src/client.rs`, and `iroh-relay/src/server.rs`
- [Iroh 1.0.3 release](https://github.com/n0-computer/iroh/releases/tag/v1.0.3)
- [Quinn 0.11.9 documentation](https://quinn-rs.github.io/quinn/quinn.html), source tag commit `b2b930a0662b18b2e351264a21e175478bb3c3f1`
- [webrtc-rs official repository](https://github.com/webrtc-rs/webrtc), examined commit `7f562590ebe5838236db4ac32f58695f939ef9f0`
- [Tailscale DERP protocol source](https://github.com/tailscale/tailscale/blob/6e0912f97994f927632b34ae9e63b53d6516a6ac/derp/derp.go) and [DERP server README](https://github.com/tailscale/tailscale/blob/6e0912f97994f927632b34ae9e63b53d6516a6ac/cmd/derper/README.md), pinned commit `6e0912f97994f927632b34ae9e63b53d6516a6ac`
- [libp2p hole-punching specification](https://github.com/libp2p/specs/blob/6b6203ee6f62938ce67efdb33498173f475851c0/connections/hole-punching.md) and [DCUtR specification](https://github.com/libp2p/specs/blob/6b6203ee6f62938ce67efdb33498173f475851c0/relay/DCUtR.md), pinned commit `6b6203ee6f62938ce67efdb33498173f475851c0`
- [rust-libp2p API](https://libp2p.github.io/rust-libp2p/), source examined at commit `170c3c81ddd80e7c58b0500563e00a09139e8545`

### Official Android documentation

- [Foreground service types](https://developer.android.com/develop/background-work/services/fgs/service-types)
- [Android 15 foreground-service type changes](https://developer.android.com/about/versions/15/changes/foreground-service-types)
- [Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)
- [User-initiated data transfer jobs](https://developer.android.com/develop/background-work/background-tasks/uidt)
- [Data-transfer background task options](https://developer.android.com/develop/background-work/background-tasks/data-transfer-options)
- [Optimize for Doze and App Standby](https://developer.android.com/training/monitoring-device-state/doze-standby)
- [Read network state / NetworkCallback](https://developer.android.com/develop/connectivity/network-ops/reading-network-state)
- [Notification runtime permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission)
- [Android 16 long-running worker guidance](https://developer.android.com/develop/background-work/background-tasks/persistent/how-to/long-running)

### Relay repository evidence

- `packages/core/src/crypto/relay_identity.rs`
- `packages/core/src/crypto/relay_identity_proof.rs`
- `packages/core/src/relay/mod.rs`
- `packages/core/src/http/server/relay.rs`
- `app/lib/provider/network/relay_send_authenticator.dart`
- `app/lib/provider/network/server/controller/receive_controller.dart`

These repository files were inspected at the baseline HEAD above; they are evidence for current Relay constraints, not modified deliverables.
