# Relay Anywhere — RA4 Transfer Architecture

**Status:** Approved for RA4A implementation

## Architecture decision

RA4 uses Option C: keep Relay's existing HTTP transfer semantics and run them over a caller-supplied authenticated stream.

Anywhere flow:

```text
Iroh QUIC
→ bidirectional stream
→ Relay inner TLS
→ mutual RelayIdentityProofV1
→ AuthenticatedRelaySession
→ HTTP/1.1
→ existing Relay v2 upload semantics
```

RA4 does not create a separate long-term Anywhere file-transfer protocol.

## Server boundary

Generalize the existing HTTP connection-serving boundary so it can consume a stream implementing `AsyncRead + AsyncWrite` rather than requiring `TcpStream`.

LAN continues to provide its normal TCP/TLS stream. Anywhere provides its already-authenticated inner-TLS stream. Both use the same high-level upload handlers.

## Reuse existing transfer semantics

Reuse unchanged or nearly unchanged:

- `FileDto` / v2 DTOs
- prepare-upload
- receive approval / `decision_tx`
- common/session
- common/save
- Android SAF behavior
- overwrite/conflict behavior
- timestamps where applicable
- streaming
- SHA-256/integrity
- progress
- cancellation
- drop guards
- Dart transfer event plumbing

Anywhere must not duplicate these semantics.

## Bounded adapters

The approved architecture requires only these transport adaptations:

1. `TcpStream`-specific server boundary to a generic `AsyncRead + AsyncWrite` stream.
2. `RequestClientInfo.ip` / `PeerIp` assumptions to a transport-neutral connection origin; never fabricate an IP for relayed sessions.
3. `ConnectionTlsCtx` derived from the actual Anywhere inner-TLS connection and carrying the `AuthenticatedRelaySession`.
4. Existing reqwest LAN client remains; Anywhere uses `hyper` `client::conn` over the authenticated stream.

High-level transfer semantics remain shared.

## Authentication before metadata

Hard invariant:

```text
Iroh path
→ inner TLS
→ mutual Relay proof
→ AuthenticatedRelaySession
→ authorization
```

No filename, file size, MIME type, `FileDto`, folder structure, or payload may be accepted before that sequence completes. Anywhere authentication failure is terminal. There is no downgrade to `LegacyLanInboundSession`, Relay, or unverified LAN semantics.

## Route restriction

Anywhere exposes only the required Relay upload routes. It does not automatically expose:

- Web Share
- browser routes
- internal/debug endpoints
- LAN discovery
- multicast
- prepare-download, unless explicitly needed later

## Client strategy

The existing LAN client stays reqwest-based. Anywhere receives a narrow HTTP/1.1 sender using `hyper` `client::conn`, because reqwest cannot naturally consume the caller-owned Iroh stream.

Both sit behind one shared high-level sender and semantic boundary. The largest implementation risk is behavioral drift between LAN reqwest and Anywhere hyper in timeout handling, errors, cancellation, streaming, and progress. Equivalent behavior tests must exercise both sender implementations.

## Multiple files and folders

RA4A supports exactly one real file. It does not map individual files to separate QUIC streams.

RA4B expands the same architecture to multiple files, folders, progress, cancellation, and existing overwrite/conflict behavior. QUIC multiplexing remains a possible later optimization.

## Large files

Transfers must stream with bounded memory, backpressure, cancellation, existing SHA-256 integrity behavior, no full-file buffering, and no cloud storage or cache. QUIC flow control operates below the existing HTTP body stream.

## Resume

RA4 V1 matches current LAN behavior. RA4A does not introduce resumability. If resume is added later, it becomes a shared transfer feature rather than an Anywhere-only protocol.

## Path migration

Transfer belongs to the authenticated QUIC connection. If Iroh changes direct → relay or relay → direct inside the same connection, transfer continues normally.

If a new QUIC connection is created, it requires fresh inner TLS, fresh mutual Relay proof, and a fresh `AuthenticatedRelaySession`. No prior approval or authentication state is silently reused.

## LAN safety

The following are non-negotiable:

- Existing LAN discovery remains unchanged.
- LAN TCP/HTTPS remains unchanged.
- Relay compatibility remains unchanged.
- LAN-only operation never initializes Iroh.
- Transfer semantics remain shared.
- Anywhere authentication failure never downgrades.
- `PathDescriptor` never becomes identity.
- `RelayId` remains the trust anchor.

## Phases

### RA4A — one real file

```text
Android selects a real file
→ authenticated Anywhere connection
→ existing prepare-upload
→ receive approval
→ existing save/session machinery
→ streaming file
→ file appears on Linux
→ bytes and SHA-256 match
```

No folders, multi-file support, or normal Home integration.

### RA4B — breadth

- Multiple files
- Folders
- Progress
- Cancellation
- Overwrite/conflict handling

### RA4C — product integration

The normal Relay Home/send flow chooses the peer. If LAN is available, use LAN; if a remote Anywhere path is available, use Anywhere. Transport is secondary UI only: Direct or Relayed. The user should not need to know Iroh or EndpointIds.

#### RA4C1 — unified resolution boundary

RA4C1 introduces the core-only `RelayDevice`, unresolved legacy-LAN candidate,
transport candidate, resolver, session-factory, and send-service boundaries.
LAN discovery remains a routing observation (alias, address, port, protocol,
fingerprint, compatibility metadata) and does not create a `RelayId`.
Verified devices are keyed only by proven `RelayId`; Relay remains a
separate compatibility namespace. A verified device may use an associated LAN
route only when that outbound route re-proves the expected RelayId; otherwise
its authenticated Anywhere route is selected.

Pre-RA3C this LAN exception applies only to the outbound initiator: the
existing HTTPS client obtains the remote Server-role Relay proof, verifies its
TLS binding, and checks the expected RelayId before transfer. It is not mutual
LAN responder authentication. Inbound legacy LAN remains
`LegacyLanInboundSession` with no Client-role proof; RA3C owns that work.

No remote-address persistence, account, presence, directory, or rendezvous
service is introduced in RA4C1. RA4C2 must define any persisted remote routing
metadata separately from trust, using only an explicit local source of truth.

## Verdict

**READY FOR RA4A IMPLEMENTATION.**
