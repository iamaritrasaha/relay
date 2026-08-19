# Relay Continuity

Relay Continuity carries device state — battery, clipboard, notifications,
messages and call status — between an Android phone and a desktop, over the
already-authenticated Relay relationship.

This document records the architecture, the trust boundary, and the exact
platform limits behind every capability that is not simply "available".

## Trust boundary

Continuity data is sensitive, so the entry point is narrow by construction.
`localsend::continuity::run_session` takes an `AuthenticatedRelaySession`, whose
only constructor is `RelayAuthCoordinator` after a verified
`RelayIdentityProofV1`. There is no conversion into that type from:

* `LegacyLanInboundSession` — the legacy LAN path, whose peer RelayId is claimed
  rather than proven;
* `LocalSendPeer` — LocalSend compatibility peers have no RelayId at all;
* a LAN discovery observation, a display name, an IP, an Iroh `EndpointId`, or a
  stored `RelayAddressV1`.

None of those can therefore open a continuity session. RA3C (mutual inbound
legacy-LAN authentication) stays deferred, and no LAN packet changed.

Three questions are kept separate, and answering one never answers another:

| Question | Answered by |
| --- | --- |
| Can we route to this device? | `RelayPairedAddress` — written by pairing |
| Is the peer who it claims to be? | `AuthenticatedRelaySession` — the RA3A proof |
| Is the device trusted? | `TrustDirectory` — a user decision |
| Did the user enable this capability? | `ContinuityPermissions` — a user decision, per capability, per device |

Pairing answers only the first. A trusted device with nothing enabled shares
nothing; `authorize_capability` denies every grantable capability until the user
turns it on, in both directions.

## Transport

Continuity has its own ALPN, `relay-continuity/1`, advertised alongside the
transfer ALPN on the same Iroh endpoint. The transfer wire format is untouched,
and the listener dispatches on the negotiated protocol. A device that has enabled
nothing is not handed a continuity accept configuration at all, so it does not
serve the protocol.

Both directions reuse the transfer path's inner TLS and the mutual
`RelayIdentityProofV1` handshake, so the stream handed to the session loop is
already encrypted and already bound to a proven RelayId. Path preference stays
`Auto`: two devices on one network get a direct path from Iroh by themselves,
which is how nearby continuity works without touching legacy LAN semantics.

Outbound dials reuse the Anywhere listener's endpoint, so a device keeps one
routing identity and one socket.

## Protocol

One versioned container, `ContinuityEnvelopeV1`, carries every capability. There
is no generic "command" payload: each remote-triggerable action is a distinct
typed struct. Nothing on the wire can name a method, a path, an Android intent,
or an executable.

Bounds are enforced on decode *and* encode, so a local bug cannot emit a frame a
peer must reject:

| Bound | Value |
| --- | --- |
| Envelope | 256 KiB, checked before allocation |
| Clipboard text | 64 KiB |
| Notification title / body | 512 B / 4 KiB |
| SMS body | 4 KiB |
| Recipients per message | 10 |
| Page size | 100 |
| Action freshness window | ±120 s |

An envelope's declared capability must match its payload, so a `Messages` body
cannot be smuggled under a `Battery` label to dodge authorization. The echoed
`sender_relay_id` must equal the proven remote id; a mismatch ends the session.
Malformed input is answered with a structured error and the session survives, up
to 16 recoverable errors; an oversized length prefix is fatal because the stream
position can no longer be trusted.

Privileged actions (`SmsSendRequest`, `CallActionRequest`,
`NotificationDismiss`) carry a `request_id` and an `issued_at_ms`. A replay
inside the window is answered as a duplicate rather than executed again; one
outside it is refused as stale.

## Capabilities and their real limits

### Battery — available

Read from `ACTION_BATTERY_CHANGED`, which is sticky, so the current value needs
no polling and the receiver only runs when the system says something changed.
Updates are published only on a meaningful change. A missing level is reported as
unknown rather than as 0%. Voltage, current and temperature are deliberately not
read. A reading older than ten minutes renders as "last known", never as live.

### Clipboard — limited on Android

> Unless your app is the default input method editor (IME) or is the app that
> currently has focus, your app cannot access clipboard data on Android 10 or
> higher.
> — [Android 10 privacy changes](https://developer.android.com/about/versions/10/privacy/changes)

Relay is not an IME and will not abuse an `AccessibilityService`, so **reading**
the Android clipboard works only while Relay is in the foreground. The capability
ships as `Limited` carrying that reason verbatim, and the Android clipboard sheet
doubles as the workaround: while it is open Relay has focus, so "Share now"
always works.

**Writing** is not restricted this way, so desktop → Android clipboard sharing
works fully from the continuity foreground service. On Android 13+ the system
shows the user its own preview of what was written.

Loop suppression is by content fingerprint plus origin: a device never returns
content whose fingerprint it just received, and never sends content whose origin
is the peer it would send to.

### Notifications — permission required, then available

`NotificationListenerService` under `BIND_NOTIFICATION_LISTENER_SERVICE`. The
user grants this in Android's own "Notification access" screen; an app cannot
grant it to itself and Relay does not try. Only app label, title, body,
timestamp and a stable key are forwarded — no extras bundles, remote views or
binary assets. Ongoing entries, group summaries and Relay's own notifications
are skipped.

### Messages — permission required; Play policy caveat

Read through the public `Telephony` content provider under `READ_SMS`, sent
through `SmsManager` under `SEND_SMS`, live delivery under `RECEIVE_SMS`.
Retrieval is always bounded by an explicit limit and cursor; the message store is
never copied wholesale.

**Relay does not become the default SMS handler.** Claiming that role purely to
unlock the feature would be an inappropriate role claim.

Separate the two questions:

* *Technical capability*: fully implemented and working on any device where the
  user grants the permissions.
* *Play distribution eligibility*: `READ_SMS`, `RECEIVE_SMS` and `SEND_SMS` are
  Google Play **restricted permissions**. A Play release needs either the default
  SMS role or an approved permissions declaration. Until that review happens,
  Messages is honest but **not Play-ready**.

### Phone — limited

| Action | API | Permission | Status |
| --- | --- | --- | --- |
| Call state | `TelephonyManager` callbacks | `READ_PHONE_STATE` | works |
| Other party's number | same | `READ_CALL_LOG` (Android 10+) | works with the permission; reported unknown without it, never guessed |
| Place a call | `TelecomManager.placeCall` | `CALL_PHONE` | works |
| Answer | `TelecomManager.acceptRingingCall` | `ANSWER_PHONE_CALLS` (API 26+) | works |
| Reject / hang up | `TelecomManager.endCall` | `ANSWER_PHONE_CALLS` (API 28+) | works |
| **Call audio on the computer** | — | `CAPTURE_AUDIO_OUTPUT` | **not possible** |

Routing live cellular call audio to a desktop requires capturing the voice-call
audio stream, which needs `CAPTURE_AUDIO_OUTPUT` — a `signature|privileged`
permission granted only to system apps. No normally distributed app can do it,
and Relay does not pretend otherwise: the Phone surface states the limitation
once, plainly.

Dial strings from the wire are validated against a conservative character set
before reaching the platform, and answer/reject/hang-up may not carry an address
at all, so remote data never becomes a free-form URI or intent.

No reflection into private telephony services, no hidden API, no root, no ADB,
no `AccessibilityService`.

### Contacts

`ContactsContract.PhoneLookup` under `READ_CONTACTS`, resolved per conversation
on the phone. Only the resulting display name is sent. There is no contact
synchronisation and the address book is never exported.

## Background behaviour

`ContinuityForegroundService` is typed `connectedDevice` —
`FOREGROUND_SERVICE_CONNECTED_DEVICE` — which is what Android defines for
interacting with a companion device, rather than `dataSync`, whose per-day
runtime is capped from Android 15. Its notification is low importance and offers
a "Turn off" action.

It starts only when at least one capability is enabled for at least one device,
and stops when the last one is turned off. **A fresh install, or an install used
purely for LAN file transfer, never runs it**, and existing transfer behaviour is
unchanged.

Reconnection is capped exponential backoff (2 s → 60 s). A peer that refuses —
not trusted, or blocked — stops the dialer entirely rather than retrying against
a decision. There is no polling loop and no wake lock.

## Activity

Continuity activity is metadata only and session-scoped: which device, what kind
of thing happened, and when. Clipboard text, message bodies, phone numbers and
contact names are never recorded, and nothing is persisted.

## Android permissions added

| Permission | Why | Play-sensitive |
| --- | --- | --- |
| `BIND_NOTIFICATION_LISTENER_SERVICE` | notification mirroring | user-granted in system settings |
| `READ_SMS`, `RECEIVE_SMS`, `SEND_SMS` | messages | **yes** — restricted permissions, declaration required |
| `READ_PHONE_STATE` | call status | standard runtime permission |
| `CALL_PHONE` | place a call from the desktop | standard runtime permission |
| `ANSWER_PHONE_CALLS` | answer / reject / hang up | standard runtime permission |
| `READ_CALL_LOG` | the other party's number | **yes** — restricted permission |
| `READ_CONTACTS` | resolve names locally | standard runtime permission |
| `FOREGROUND_SERVICE_CONNECTED_DEVICE` | the continuity connection | normal permission |

All of them are inert until the user enables the matching capability for a
specific device.
