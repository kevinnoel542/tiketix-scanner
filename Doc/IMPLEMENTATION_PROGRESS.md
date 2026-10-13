# TiketiX Scanner: Implementation Progress

Updated: 12 October 2026.

This document records the scanner work implemented so far in Flutter and the
companion Laravel project. Implemented code is not the same as a tested production
release. Pending verification and deployment are listed separately below.

## Current Workflow

```text
Organizer adds scanner staff and an event/gate shift
  -> Organizer issues an expiring invitation
  -> Staff enters invitation and matching phone number
  -> Phone OTP verifies activation
  -> Device signing key is registered
  -> Staff creates a six-digit local PIN
  -> App lists only assigned events
  -> Staff starts an active event session
  -> Online scanning, or authorized offline fallback
  -> Saved offline scans sync with the server
  -> Shift expiry blocks further scanning
```

Scanner staff is separate from organizer dashboard team membership. Creating
scanner access does not grant dashboard, finance, payout, KYC or event-editing access.

## Implemented In Flutter

### Activation And Local Lock

- Invitation and matching phone-number activation through the v2 scanner API.
- OTP entry, resend cooldown and activation error handling.
- Device signing-key generation and proof of possession during activation.
- Six-digit local PIN creation and confirmation.
- Salted PBKDF2 PIN verification; five failed attempts trigger a five-minute lockout.
- Backgrounding an unlocked scanning/assignment view returns it to the PIN lock.
- Unlock rechecks current server configuration and assigned-event authority.

The PIN unlocks an already-activated installation. It is not a server credential
and cannot by itself activate another phone.

### Assigned Events And Shift Times

- Assigned-event list rather than a list of all TiketiX events.
- Event session binds scanning to the selected assignment, event and gate.
- Session start requires an active shift on the server.
- Session expiry is returned by Laravel and cannot outlive the shift.
- The latest local change checks expiry every second while the scanner view exists.
- On expiry, the app stops the camera, blocks new scan attempts, closes an activity
  route if necessary and displays an access-ended message.
- Saved offline records are retained for recovery instead of being deleted.

The latest automatic-expiry UI change still needs runtime and physical-device tests.
Mobile operating systems may suspend timers in the background; server checks remain
the online authorization boundary.

### Online Scanning And Activity

- Camera scanning and manual ticket-code entry.
- Validation followed by explicit admission confirmation.
- Included-item redemption where returned by the online API.
- UUID-bound scan retries for uncertain network outcomes.
- Duplicate-scan results and success/error feedback.
- Assigned-event attendance statistics, attendee search/pagination and scan history.
- Periodic device heartbeat with reported mode and unsynced-scan count.

### Supervisor Controls

- Same-event staff/device overview for gate supervisors.
- Gate-staff invitations and replacement activation workflow.
- Move gate, end sessions, revoke assignment and revoke device controls.
- Revoke existing offline packages for a selected assignment.

Supervisors cannot manage another supervisor's authority through these endpoints.
The offline-disable operation revokes existing packages; it is not documented as a
permanent ban on all future package downloads.

### Offline Scanning And Recovery

- Device-encrypted, server-signed event packages.
- Signature verification and device/package identity checks before use.
- Offline entry validation and admission recording; included-item redemption remains online.
- Encrypted SQLite state with its encryption key in secure storage.
- Admission queue and local checked-in state are committed together before positive feedback.
- Server-time anchor advanced using a monotonic stopwatch during the running app process.
- Queue limit of 2000 pending scans; sync requests contain at most 50 records.
- Matching sync receipts are required before removing saved records.
- Retried batches retain the same scan UUIDs.
- Recovery uploads preserve expired/revoked submissions for organizer review.
- Signout/new activation is blocked while unsynced records would be stranded.

Offline limits: packages contain at most 2000 tickets, last at most 120 minutes,
and never extend beyond the issuing session's expiry. After reopening the app,
an online time anchor is required before offline admission. Disconnected phones
cannot immediately observe revocation or duplicate admission on another phone.

### API And Android Release Preparation

- Release API configuration requires a valid HTTPS origin.
- Requests sign method, exact URI, timestamp, nonce, body, credential and session hashes.
- Credentials and software signing/encryption seeds use Flutter secure storage.
- Short-lived access credentials with serialized refresh handling.
- Android source manifest disables backup and release cleartext traffic.
- Debug-only cleartext support remains available for local development.
- Release signing configuration uses an external private key, not a debug-key fallback.
- A private release key was created outside the repository.
- Release build script prepares obfuscation, symbol output and APK SHA-256 output.
- Private repository created: https://github.com/kevinnoel542/tiketix-scanner

An inspected, verified release APK has not been delivered. Key backup, APK distribution,
update verification and final merged-manifest checks remain release requirements.

## Implemented In Laravel

- Dedicated scanner staff, event assignments, invitations, devices and sessions.
- Hashed access/refresh credentials and persistent request-nonce replay records.
- v2 activation, profile, session, scan, activity, supervisor and offline endpoints.
- Invitation expiry: 30 minutes. OTP expiry: five minutes, maximum five attempts,
  with a 60-second resend cooldown.
- Approved-device key proof and replacement-device restrictions.
- Access credential expiry: 15 minutes; refresh expiry: 12 hours.
- Current staff/organizer/event ownership, activity, suspension, revocation and shift checks.
- Transactional admission and scan-id/request binding for idempotent retries.
- Active paid-ticket filtering for online validation and offline packages.
- Signed/encrypted offline manifests and per-device package ownership checks.
- Late/revoked offline submissions are retained as REVIEW_REQUIRED, not auto-admitted.
- Organizer-scoped offline review with notes and audit records.
- Organizer Gate Staff management UI for assignments, invitations and devices.
- Nonce/activation cleanup command and scheduler registration.
- Legacy v1 API defaults disabled in production; its alternate admission paths still
  need review before explicitly enabling it.

### Request Limits

| Scope | Source limit |
|---|---|
| General scanner credential and IP | 120 requests/minute by default |
| Aggregate scanner traffic from one IP | 600 requests/minute |
| Activation endpoints | 10 requests/minute |
| Offline package download | 2 requests/minute |

Excess traffic is throttled with HTTP 429. Limits do not replace authorization or
edge protection. Validate throughput for many phones sharing a venue IP, and check
the deployed proxy and persistent rate-limit cache before production use.

## Local Database Work Completed

The three scanner migrations finished on local database new_tiketix:

- 2026_10_12_120000_create_scanner_staff_access
- 2026_10_12_130000_create_scanner_offline_access
- 2026_10_12_140000_add_scanner_operational_controls

Missing assignment, staff-device and offline-scan tables were created. A slow,
partially completed migration was recovered without deleting existing records.
The Gate Staff page was also made independent of optional offline-review tables
while setup is incomplete. The refreshed browser page still needs confirmation.

This was local database work, not a server migration or deployment.

## Verification Evidence And Limits

Existing test files:

- test/scanner_staff_security_test.dart
- test/scanner_offline_test.dart
- test/widget_test.dart
- Laravel tests/Feature/ScannerApiTest.php

Earlier isolated runs passed Flutter security/offline tests and Laravel scanner
tests. Later persistence, UI and expiry changes require another complete current-tree
run; earlier passing results must not be treated as proof for the latest revision.
PHP syntax and whitespace checks passed for the latest rate-limit/expiry edits.

The security audit on 12 October stopped during reconnaissance when an independent
worker hit the account usage limit. No vulnerabilities were independently validated.
It did not certify the app or production deployment. Partial report:
/home/kevin/security-audit-skill/tiketix-scanner/run-1/REPORT.md

## Remaining Before Production Approval

1. Run analysis and the full relevant tests against the latest Flutter/Laravel trees.
2. Test camera, OTP, PIN, shift expiry and background/resume on a real Android phone.
3. Test cross-event/organizer denial, replay, refresh reuse and concurrent revocation.
4. Test offline persistence, interrupted sync, late recovery and organizer review.
5. Finish independent security validation, including legacy admission paths.
6. Check PIN lockout under clock changes and actual device secure-storage behavior.
7. Build and inspect a signed release APK; verify manifest, signing identity and updates.
8. Confirm production feature flags, migrations, scheduler and rate-limit storage at deployment.
9. Provide a trusted APK download/update workflow and retain signing-key backups safely.

Current status: substantial scanner implementation exists locally, but physical-device
validation, complete security review and verified production release remain unfinished.
