# Offline Scanning And Sync

Status: future design. Keep offline scanning disabled until the safeguards and tests in this document are implemented.

## Online Preferred, Offline Fallback

Two disconnected phones can both accept the same ticket before either syncs. No independent offline database can eliminate that conflict without communication between gates.

Prefer online check-in. Sync whenever connectivity becomes available. Offline acceptance must be visibly marked as provisional rather than globally confirmed.

## Event-Specific Packages

Never download a TiketiX-wide ticket database. Each package belongs to one event, approved device and staff assignment, optionally narrowed by gate/ticket eligibility.

Example:

```text
Device: SCN-72AQ
Event: Greenlight Experience
Gate: Gate B
Valid until: 13 Dec 2026 03:00 Africa/Dar_es_Salaam
```

The example expiry is illustrative: the actual package cannot authorize scanning beyond the staff assignment. A later upload deadline is separate from scan authorization expiry.

Knowing another event ID must not permit downloading its package. Laravel checks identity, device, event assignment and package entitlement before issuing or refreshing it.

## Package Contents And Protection

Include event ID, device/assignment binding, package ID, version, issuance time, scan-validity end and the minimum ticket verification records. Avoid unnecessary names, phone numbers, emails and QR secrets.

Use a reviewed format with authenticated encryption and a server integrity signature. Bind encryption/signature metadata to event, assignment, device and package version. Use established cryptographic libraries rather than custom algorithms.

Enroll a per-installation key securely and protect private keys with platform facilities where available. Do not encrypt all packages using one secret embedded in the APK. A posted device ID is not a cryptographic identity.

Verify integrity, recipient binding and validity before opening a package. Prevent older package rollback where feasible. Store packages encrypted, exclude sensitive data from backups/logs, and delete expired local data under a defined retention policy.

Encryption cannot make an authorized or compromised device incapable of reading data it legitimately needs. Minimize the package accordingly.

## Visible Offline State

The scanner always displays event and gate. Entering offline fallback asks the worker to confirm:

```text
Greenlight Experience
Gate B
12 December 2026
Start Offline Scanning
```

Show a distinct offline state and queued submission count. Do not suggest that every disconnected scan is already confirmed by the server.

## Offline Scan Record

```text
scan_uuid
ticket_id
event_id
device_id
staff_id
assignment_id
gate_id
scanner_session_id
offline_package_id
package_version
local_scanned_at
```

Generate a fresh UUID for each operation with a standard library. A value beginning `01J...` is typically a ULID, not a UUID; choose one format explicitly and validate it consistently.

Protect queued records against tampering with the enrolled device key and package/session binding. Record monotonic sequence information where useful. Store the server receipt time separately from the claimed local scan time.

## Sync Validation

Flutter submits bounded batches to an authenticated versioned sync endpoint. Logical example: `POST /scanner/sync`.

Laravel checks:

1. Identity and device proof; whether the device is approved or revoked.
2. Assignment/session/package ownership and historical validity.
3. Ticket belongs to the assigned event and is eligible for entry.
4. Gate and ticket restrictions, payment/refund/cancellation state.
5. Package authenticity/version and whether the reported scan is plausible within its validity window.
6. Whether this operation or ticket admission has already been processed.

Never trust submitted staff/event/gate IDs or local timestamps as authority. A worker can change the phone clock or modify the app. Historical acceptance after revocation needs an explicit policy supported by trustworthy evidence; uncertain records enter conflict/manual review rather than automatically admitting someone.

## Idempotency And Concurrent Admissions

Use database uniqueness for operation IDs, with payload binding. An exact retry returns the existing result; reuse of an ID with different content is rejected.

Operation idempotency is not ticket uniqueness: two distinct scan UUIDs can target the same ticket. Enforce the admission invariant separately with database locks/constraints so only one canonical admission commits.

Return per-record accepted, duplicate, conflict or rejected outcomes. Retrying a partial batch must not duplicate accepted scans. Keep rejected/conflicting attempts in an appropriately minimized audit trail.

## Revocation And Conflicts

Revocation stops online scans and new package downloads immediately, but an already-downloaded package may continue working while the phone is disconnected. Short package validity bounds that exposure; it does not eliminate it.

Provide a narrowly scoped way to upload historical evidence from a revoked device without restoring normal scanner permissions. Default to quarantining questionable submissions. The server must distinguish valid pre-revocation evidence from untrusted backdated claims.

For duplicate tickets admitted at separate disconnected gates, preserve both observations and flag the conflict for the supervisor. Sync cannot undo a person physically admitted already.

## Required Tests

- Cross-event and cross-organizer package download denied.
- Wrong device, altered package and altered record rejected.
- Expired package cannot authorize new scans.
- Clock changes do not automatically bypass expiry or revocation.
- Exact sync retries are idempotent; conflicting payload reuse is rejected.
- Concurrent distinct scans cannot create two canonical admissions.
- Partial batch retries preserve prior results.
- Cancelled/refunded tickets handled according to explicit offline policy.
- Revoked-device evidence upload cannot restore scan access.
- Two disconnected devices produce an explicit conflict, not silent double confirmation.
