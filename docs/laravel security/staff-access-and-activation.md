# Staff Access And Activation

Status: proposed design, not implemented functionality.

## 1. Separate Team From Scanner Staff

Keep the existing organizer team invitation system for dashboard collaborators such as managers, event managers, finance and support.

Temporary gate workers receive a scanner-only staff profile. They do not need thirty permanent organizer accounts when thirty people are hired for one evening.

Permanent staff and supervisors may link a normal TiketiX identity to a scanner profile, but that link must not automatically grant dashboard permissions. Temporary staff authentication needs a Laravel principal/guard or explicitly restricted identity model; it must never accidentally become a normal website login.

Example assignment:

```text
Name: John M.
Phone: +255...
Event: Greenlight Experience
Gate: Gate B
Role: Gate Staff
Access starts: 12 Dec 2026 14:00 Africa/Dar_es_Salaam
Access ends: 13 Dec 2026 02:00 Africa/Dar_es_Salaam
```

Store instants consistently in UTC and display the event's timezone. Access ends at the explicit shift/assignment end, not an ambiguous calendar-day boundary.

## 2. Organizer Gate Management

Navigation: Event -> Gate Management -> Add Gate Staff.

Form fields:

- Name and normalized phone number.
- Role: Gate Staff or Gate Supervisor.
- Gate belonging to the event.
- Access start and end, with end later than start.

The staff list shows name, gate, role, invitation/activation status, device status and access period. Do not expose invitation secrets to unauthorized dashboard roles.

The organizer cannot invent a worker's password or distribute shared credentials through WhatsApp.

## 3. Activation Invitation

Create a single-use activation invitation scoped to organizer, event, staff, phone and assignment. Suggested initial invitation lifetime: 30 minutes.

Offer a cryptographically random secure link, for example `/scanner/activate/{token}`, or a short activation code. A six-digit code is convenient but has low entropy: require strict attempt limits, expiration, phone/assignment binding and abuse controls. Do not treat the code alone as authentication.

Store token/code verifiers, not plaintext invitation secrets. Do not log secrets or expose them in analytics. Activation pages must be noindex and must not leak token URLs through referrers.

Invitation redemption must be atomic and one-time. Issuing a replacement invalidates the previous invitation. Renewal is an explicit authorized action.

## 4. First-Time Activation

```text
TiketiX Scanner
Activate Scanner Access
Invitation code / invitation link
Phone number
Continue
```

The server checks invitation validity, matching phone, valid assignment and unused status. It sends an OTP to the bound phone, with a suggested five-minute lifetime.

OTP issuance and verification need independent request/attempt limits, resend cooldowns, hashed storage and single-use consumption. Return non-enumerating errors where possible.

After phone verification, register the installation and require the applicable organizer/supervisor approval policy. An invitation can authorize a controlled first-device enrollment, but arbitrary new installations must not be automatically approved. Define that policy explicitly.

Never consume the invitation before the activation flow can safely finish; use an activation challenge and transaction to prevent partial enrollment or simultaneous redemption.

## 5. Local Scanner PIN

Staff chooses and confirms their own six-digit PIN. It unlocks an already-enrolled device; it is not a server login credential or a new-device activation secret.

Protect local credentials using platform secure storage and, where feasible, hardware-backed keys and biometric/device authentication. Do not store plaintext PINs. A short PIN verifier remains vulnerable to offline guessing on a compromised device; avoid relying on it to protect an exported token.

Apply local retry limits and lockout. Recovery requires re-verification/approval, not an organizer reading or setting the PIN.

John sharing his PIN with Peter must not let Peter activate a different phone. An unknown device receives a new-device-not-authorized response and needs separate activation/approval.

## 6. Sessions And Event Selection

The assigned-events endpoint returns only the current staff member's authorized events. `/scanner/my-events` is a proposed logical endpoint; map it to a versioned API during implementation.

One assignment can open directly to its event. Multiple assignments display only those events, with date, venue and gate. Never return a global event list and rely on Flutter to filter it.

Starting scanning creates a session bound to:

```text
staff_id
device_id
assignment_id
event_id
gate_id
started_at
expires_at
revoked_at
```

Temporary identities use `staff_id`; an optional linked `user_id` does not replace assignment checks. The backend derives identity from authentication rather than trusting posted IDs.

The camera screen prominently shows event, gate, staff and connection state. Changing events requires exiting scanning and starting a session for another valid assignment; no casual event dropdown inside the camera.

Token expiry must actually be enforced by Laravel, not merely returned as `expires_at`. Every protected endpoint checks scanner-only scope, current device approval, assignment validity and session state. A token bound to a device needs server-verified binding; a freely editable device ID is not proof of possession.

## 7. Gate Supervisor

Within explicitly delegated events, a supervisor may:

- View gate staff, devices and check-in totals.
- See online/offline state and queued-sync status, marked with last-contact time.
- Approve replacement devices and issue replacement activation.
- Move staff between gates within the delegated event.
- Revoke scanner access.

They cannot manage payouts, KYC, financial settings, organizer ownership or broader organizer-team membership. Require additional confirmation for sensitive device/assignment changes and audit each action. Device status cannot reliably be known in real time when disconnected.

## 8. Lost Phone And Removed Staff

Revoking a phone invalidates its sessions/tokens and blocks new package downloads and online scans. Replacement activation enrolls a different installation; the old device remains revoked.

Removing staff revokes active assignments and online sessions immediately. All API paths, including event lists, attendee lookup and sync, must recheck authorization.

Retain historical offline submissions for audit, but do not automatically accept them based on a client-provided timestamp. Revocation-aware sync adjudication is defined in [Offline Scanning And Sync](offline-scanning-and-sync.md).

## 9. APK Distribution

An official HTTPS page such as `/scanner/download` may show Android support, release version, download link and SHA-256 checksum. Release signing is mandatory; keep the signing key outside source control and protect backups. Use the same authorized key for updates.

Download links may be public or require login. Neither approach replaces backend authorization; copied APKs must confer no access. A checksum helps verify file integrity but is not a substitute for app signing.

Expiration concepts are separate:

| Item | Proposed lifetime |
|---|---|
| APK download URL | May be permanent |
| Activation invitation | 30 minutes |
| Phone OTP | 5 minutes |
| Device activation challenge | Short-lived and one-time |
| Event assignment | Explicit shift/event access window |
| Scanner session | Bounded by token, device and assignment validity |
| Offline package | Explicit, short validity bounded by assignment |
