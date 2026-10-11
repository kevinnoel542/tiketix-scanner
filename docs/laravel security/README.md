# TiketiX Scanner Security Design

Status: proposed implementation specification. These documents do not mean the features are already implemented or security-tested.

## Objective

Keep Organizer Team, but separate it from Gate Scanner Staff. A temporary gateman must not need organizer dashboard access just to scan tickets.

```text
Organizer Account
|-- Organizer Team
|   |-- Manager
|   |-- Event Manager
|   |-- Finance
|   `-- Support
`-- Scanner Staff
    |-- Gate Staff
    `-- Gate Supervisor
```

Organizer Team is for permanent dashboard collaborators. Scanner Staff is for narrowly authorized gate operations. Role names here are proposed; implementation must map them explicitly to existing permissions rather than silently granting new privileges.

## Documents

- [Staff Access And Activation](staff-access-and-activation.md): invitations, phone verification, device approval, local PIN, event sessions, supervisor permissions and revocation.
- [Offline Scanning And Sync](offline-scanning-and-sync.md): event/device packages, encryption, duplicate prevention, conflict handling and offline limitations.
- [Implementation And Validation](implementation-and-validation.md): Laravel data model, Flutter responsibilities, current gaps and acceptance tests.

## Security Boundary

Assume anyone can obtain, inspect or modify the APK and call the API without the official app. The Laravel server must enforce authorization independently on every protected request.

Possession of the APK, an event ID, a local PIN or a client-generated device ID is not authorization. Access requires a valid staff identity, approved device, active event assignment and valid scanner session.

Gate staff cannot access organizer dashboards, revenue, order management, customer databases, payouts, event editing, team management or KYC. Scanner responses expose only the minimum ticket information needed for entry.

## Expected Workflow

```text
Organizer creates event
-> Adds gate staff: name, phone, gate and shift
-> TiketiX creates expiring activation invitation
-> Staff installs the signed scanner APK
-> Opens invitation or enters invitation code
-> Verifies phone by OTP
-> Registers and obtains approval for the device
-> Creates a local scanner PIN
-> Sees only assigned events
-> Starts an event/gate-specific scanner session
-> Scans online; uses authorized offline fallback if enabled
-> Syncs queued records when connectivity returns
-> Access expires at the assignment end time
```

Ten, fifty or one hundred simultaneous events must not broaden an individual staff member's access. The event list and every API operation remain assignment-scoped.

## Delivery Phases

1. Secure Laravel authorization, token expiry, device approval and event assignments.
2. Implement scanner-only invitations, OTP activation and Flutter session handling.
3. Add gate management, supervisor operations, revocation and auditing.
4. Implement offline packages only after integrity, sync and conflict tests pass. Keep offline scanning disabled until then.

No security design can guarantee that a lost phone will stop working immediately while it is fully disconnected. Offline package validity and operational policy must bound that risk.
