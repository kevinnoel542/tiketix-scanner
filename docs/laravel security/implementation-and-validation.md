# Implementation And Validation

Status: proposed architecture and source-inspection notes. No implementation or full security audit is implied.

## Laravel Data Model

Suggested logical entities:

```text
users
organizers
organizer team membership (reuse existing organizer_user where appropriate)
events
event gates
scanner_staff
event_scanner_assignments
scanner_invitations
scanner_devices
scanner_sessions
scanner_offline_packages
ticket_scans
```

Reuse the current scanner device/audit entities where safe. Avoid creating competing membership systems without a migration plan.

Relations:

```text
Organizer
|-- Organizer Team
`-- Event
    |-- Gates
    |-- Scanner Assignments -> Scanner Staff
    |-- Authorized Device/Assignment Bindings
    |-- Scanner Sessions
    |-- Offline Packages
    `-- Scan History
```

Scanner staff needs an organizer boundary, name, normalized phone, status and optional linked permanent user. Decide explicitly whether a worker can belong to multiple organizers; matching phone numbers must not silently merge identities or permissions.

Assignments need staff, event, gate, role, starts_at, ends_at and revoked_at. Sessions cannot outlive the assignment. Device records need enrollment identity/key information, approval/revocation metadata and auditable ownership.

Invitation and OTP records need hashed verifiers, expiry, attempts, consumption and binding to an activation challenge. Use transactions and uniqueness constraints for one-time activation and scan idempotency.

## Backend Authorization

Create one shared scanner authorization policy/service used by event listing, details, validation, check-in, lookup, attendees, history, stats, package downloads and sync. Endpoint-specific filtering is not enough if another endpoint bypasses the same boundary.

Server requirements:

- Scanner-only authentication and token scopes; no dashboard or financial privileges.
- Real token expiry, rotation where needed, and immediate online revocation.
- Approved-device/session binding, not trust in a submitted device ID.
- Current assignment checks for every event operation.
- Gate/role checks for supervisor operations.
- Rate limits for activation, OTP, login and API use without blocking legitimate gate throughput unnecessarily.
- Minimal attendee disclosure and no raw credentials, activation secrets or complete QR tokens in logs.
- Auditable staff, device, assignment and scan changes.

Existing global-scanner access must not be available to ordinary staff. Replace or isolate the email-based global exception with an explicitly controlled privileged workflow if it is still needed.

## Flutter Responsibilities

- Enforce HTTPS for release API configuration; never bypass certificate validation.
- Keep tokens and device private keys in secure platform storage.
- Never store account passwords or embed backend/API master secrets.
- Support invitation activation, OTP, pending approval, approved, blocked, revoked and expired states.
- Store token expiry for user experience, while relying on Laravel enforcement.
- Resume valid sessions instead of clearing them automatically at every startup.
- Use a local PIN/biometric lock for approved-device convenience, not server authorization.
- Display only assigned events and lock the camera view to the selected event/gate session.
- Clear sensitive session/package data appropriately on logout, expiry or revocation.
- Keep demo/preview mode visibly separate from real admission and disable inappropriate release shortcuts.
- Sign production releases with a protected release key, not the debug key.
- Provide a trusted update/distribution path and supported-version policy.

## Current Source Observations

These observations were made during the October 10, 2026 discussion and should be rechecked against the implementation branch:

| Area | Observation |
|---|---|
| Laravel event access | Organizer membership currently grants access across that organizer's events rather than explicit event assignments. |
| Device enrollment | Default scanner device status is approved. |
| Token lifetime | Login returns an expiry, but token creation does not set it; Sanctum global expiration is null in source configuration. |
| Scanner login | Password verification is followed by token issuance without scanner membership or second-factor checks in that method. |
| Global access | Configured email addresses can receive global scanner access. |
| Flutter storage | Token uses flutter_secure_storage; the storage service does not save the password. |
| Flutter device identity | A local random device ID is stored in preferences; it is not cryptographic proof of the physical device. |
| Flutter expiry | Login does not retain the returned expiry. |
| Flutter startup | Initialization clears the local saved session without revoking the old server token. |
| Release signing | Android release configuration currently uses the debug signing key. |
| API configuration | API URL comes from a build-time value; URL construction does not enforce HTTPS. |
| Offline mode | Currently disabled until secure manifests are available. |

Production configuration, actual APK artifacts, infrastructure and hardware-backed storage availability were not validated by that source inspection.

## Acceptance Tests

1. Gate staff cannot access organizer, admin, payout, KYC or team-management APIs.
2. A worker assigned to Event A cannot list, inspect, scan or export Event B, including another event from the same organizer.
3. Changing event, gate, staff or device IDs in a request cannot expand access.
4. Expired/revoked assignments and tokens are rejected server-side.
5. New devices cannot self-approve by posting an approved status.
6. A copied PIN is insufficient to activate another installation.
7. Invitation/OTP brute-force limits, expiry and atomic single-use handling work under concurrent requests.
8. Supervisors cannot operate outside delegated events or grant themselves broader roles.
9. Revocation covers every scanner endpoint, not only check-in.
10. Replayed check-ins do not create duplicate admissions.
11. HTTP release configuration fails safely; certificate verification is never disabled.
12. Production APK is release-signed and no credentials/signing keys appear in version control or logs.
13. Session resume, local lock and expired/blocked UI behave correctly on physical Android devices.
14. Offline requirements pass before enabling offline mode; see the separate offline specification.

Use isolated dummy accounts and events for security validation. Do not probe other organizers' production records.

## References

- [Android app signing](https://developer.android.com/studio/publish/app-signing)
- [OWASP Mobile Application Security Verification Standard](https://mas.owasp.org/MASVS/)
