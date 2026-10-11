# TiketiX Scanner: Flutter Gap Analysis and Implementation Plan

Reviewed: 2026-10-12. Status: planning document, not implemented functionality.

## Scope and Evidence

Compared this Flutter project and the Laravel scanner API against
`/home/kevin/Downloads/TiketiX_Flutter_Scanner_Laravel_Workflow.md`.
Backend companion: `../../tiketiX/docs/scanner-workflow-gap-analysis.md`, relative
to this project's root. Existing proposals: [Laravel security](laravel%20security/README.md).

Static review only: no physical-phone, live activation, APK installation or
production load tests were performed for this document.

Primary evidence:

- `lib/services/scanner_api.dart`: current API paths, authentication and errors.
- `lib/services/storage_service.dart`: token and preference storage.
- `lib/state/app_controller.dart`: startup, access states and preview mode.
- `lib/models/scanner_models.dart`: response models.
- `lib/screens/`: login, events, scanning, attendees, history, progress/settings.
- `pubspec.yaml`: dependencies and app version.
- `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`.
- `test/widget_test.dart`: existing model tests.

## Summary

This is an online scanner app foundation, not yet the complete temporary gate
staff app described in the workflow. Preserve camera scanning and event-pass
handling. Add activation, device proof, secure resume/unlock and assignment-bound
sessions before treating it as ready for scanner-only temporary staff.

The Laravel API, not the Flutter screen or APK download restriction, must make
all authorization decisions. Hiding events or navigation is not access control.

## Current Coverage

| Area | Status | Evidence / missing work |
| --- | --- | --- |
| Email/password login | Existing | `ScannerApi.login`; requires a normal backend user today. |
| Secure token storage | Existing | `flutter_secure_storage`; verify release device behavior before claiming hardware-bound protection. |
| App restart/resume | Missing desired behavior | `AppController.initialize` clears the stored session on startup. No local PIN resume workflow. |
| Device identity | Partial | Random installation ID in preferences; not a device key or proof of possession. |
| Device registration/status UI | Partial | Registration and pending/blocked/access states exist; not invitation-based activation. |
| Invitation + SMS OTP | Missing | Add activation/challenge screens and API methods. |
| Local scanner PIN | Missing | Create, confirm, unlock and recovery needed; PIN is not an API credential. |
| Event selection | Partial | Current backend returns organizer-permitted events; assignment/gate/shift model missing. |
| QR camera and admission | Existing | `mobile_scanner`, validation then check-in/result flow. |
| Event-pass item redemption | Existing | Models and scan flow support included-item redemption. |
| Attendees/history/stats | Existing | Online API-backed views; tighten role/data visibility with backend. |
| Network error handling | Partial | 401, timeout, network and unreadable response handling exist; retry/offline/session lifecycle need work. |
| Offline scanning | Missing | Keep disabled until secure package and durable queue implementation is complete. |
| Offline sync | Missing | API exposes sync status, but app has no complete durable package/queue upload workflow. |
| Refresh and expiry handling | Missing | Login stores token but does not track `expires_at` or rotate refresh credentials. |
| APK release signing | Release blocker | Release Gradle config currently uses the debug signing key. |
| Version compatibility | Missing | Registration sends hardcoded `1.0.0`; no complete minimum-version/update flow. |
| API host safety | Partial | `API_URL` compile-time configuration; no explicit release HTTPS validation in the API client. |
| UI consistency | Partial | Material/Cupertino dependencies today; no Lucide dependency or bundled Instrument Sans declaration in pubspec. |
| Automated tests | Partial | Five model parsing/permission tests in `test/widget_test.dart`; no complete activation/camera/offline integration suite. |

Preview mode returns local demo results. It is not a backend authorization bypass,
but a production app must not let staff mistake demo admissions for real ones.
Remove preview from production builds or make a separate unmistakable demo build.

## Responsibilities Between Projects

| Laravel owns | Flutter owns |
| --- | --- |
| Staff tenancy, assignments, roles, shifts | Display only returned assignments and shift/gate context |
| Invitation/OTP validation and throttles | Activation forms, resend countdown and clear error states |
| Device approval, revocation and key registration | Generate/protect installation keys and prove possession |
| Token/session expiry and authorization | Secure storage, refresh handling and local unlock |
| Final online ticket/admission decision | Camera lifecycle, duplicate scan debounce and truthful result UI |
| Signed package issuance and sync acceptance | Verify/decrypt packages and persist queued scan records |
| Global admission uniqueness/conflict resolution | Preserve per-scan IDs and handle per-record acknowledgments |
| Minimum version policy and APK publication | Actual app version reporting and safe update experience |

Never derive access from a cached `canScan` flag alone. Revalidate online access
on resume; offline requires its own explicit, valid package policy.

## Contract to Agree Before Building Screens

Keep current `/api/v1/scanner` paths or introduce a coordinated new version.
The workflow's `/api/scanner/v1` spelling is different; changing only one project
breaks the app. Existing paths are:

```text
GET /health; POST /auth/login; POST /auth/logout
GET /session/me; GET /events; GET /events/{event}
POST /devices/register; POST /validate; POST /check-in; POST /sync-checkins
GET /lookup; GET /history; GET /attendees; GET /stats; GET /sync/status
```

Create shared fixture examples for configuration, activation, OTP, approval,
sessions, refresh, package metadata, scan results and batch acknowledgments.
Current login expects top-level `access_token`; current errors parse
`error.code`/`error.message`. Do not switch envelopes without updating parsers.

Agree stable codes for expired invitation, incorrect/expired OTP, resend cooldown,
device pending/revoked, assignment not started/expired, wrong event, session
expired, unsupported version, duplicate admission and offline conflict.

## Implementation Order

### Phase 0: Release Safety and Existing Online Reliability

- Coordinate Laravel token expiry/scopes/device authorization fixes first.
- Reject missing or non-HTTPS API hosts in production builds; keep explicitly
  separate local development configuration. Never bypass TLS certificate checks.
- Apply timeout to the entire request including response body consumption.
  Bound retry/backoff; do not blindly replay a state-changing admission after
  an unknown outcome without an idempotent request contract.
- Replace debug release signing with a private release key, backed up outside
  source control. Never commit keystores/passwords. Test upgrade over prior APK.
- Report the real build version rather than the hardcoded registration value.
- Isolate preview mode from production and show real network/auth failures.

### Phase 1: Secure Online Activation and Unlock

Build the following states/screens as one coherent flow:

```text
Activate access -> Invitation + phone -> OTP -> Approved device
-> Create local PIN -> Assigned event(s) -> Start event/gate session -> Scan
```

- Support expired/revoked/used invitations, invalid phone, OTP errors, cooldown
  and pending approval without silently returning to a generic login form.
- Generate an installation key pair with maintained platform/library tooling.
  Protect private key material with Android Keystore-backed storage and verify
  actual supported-device behavior. Send only public keys/proofs to Laravel.
- Implement local PIN create/confirm/unlock with attempt limits and safe reset.
  Do not store plaintext PINs, use PIN as a server password or promise that a
  six-digit PIN alone resists extraction/brute-force attacks.
- Preserve valid credentials across restarts; replace unconditional startup
  clearing with locked/resume states. Backgrounding locks the scanner according
  to an agreed policy. Online resume checks device/assignment/session authority.
- Store secrets in secure storage, non-sensitive preferences in preferences.
  Cached event data does not grant admission rights.
- Track expiry and rotate refresh credentials if the backend implements them.
  Handle 401, revocation and unsupported versions with distinct user states.
- List only assignments from the API; skip selection only when one is eligible.
- Start a server-issued event/gate session. Make event, gate, staff and connection
  status obvious. Switching events ends the previous scanning context.

Done when an invited temporary staff member can activate and scan only the
assigned event, relaunch/unlock safely, and is blocked after expiry/revocation.

### Phase 2: Camera, Operations and Distribution Polish

- Test permission denied/permanently denied, camera unavailable, torch, pause,
  resume, rotation, app backgrounding, repeated QR frames and slow responses.
- Use a short local duplicate debounce for usability; server admission remains
  the authority. Never show success merely because a QR parses locally.
- Preserve validation/confirmation and included-item redemption behavior.
- Restrict attendee/history views to role-required data. Do not cache all buyer
  contact information or financial records on gate phones.
- Add update-required UI, version/checksum information and official download
  flow. APK can be copied: security must still hold when everyone has it.
- Use compact TiketiX layouts, neutral surfaces, restrained green and clear
  red/amber status colors. Avoid large gaps, nested cards and heavy focus halos.
- If matching the reusable design guide, select a maintained Flutter Lucide
  package and bundle the chosen font. Do not install Laravel/Flux components
  into Flutter; use Flutter-native dialogs and controls.

### Phase 3: Secure Offline Fallback

- Add an encrypted persistent local database using a maintained solution after
  deciding package/key format with Laravel. Preferences are not an offline DB.
- Download only authorized event/device/assignment packages; verify authenticity,
  integrity, version and expiry before use. Decrypt only on the approved device.
- Display explicit offline mode and confirm event/gate before starting.
- Persist UUID-based scan records before reporting offline acceptance. Store
  event, device, assignment/session, gate, package version, local time and proof.
- Keep queued records through restart, battery loss and transient networking.
  Sync bounded batches with backoff and per-record acknowledgments; retain failed
  or quarantined records for review instead of silently discarding them.
- Show queue count, last successful sync, package validity and conflicts. Do not
  mark a whole batch delivered when only some records were acknowledged.
- Logout/reset warns about unsynced records and follows the agreed preservation
  policy. Revocation stops new packages; historical uploads follow server policy.
- Address refunds/cancellations and expired snapshots. Client clock changes must
  not extend access; client timestamps are not trusted historical evidence.

Two disconnected phones can admit the same ticket before syncing. No animation,
encryption or UUID removes that limitation. Prefer online operation and clearly
communicate bounded offline fallback behavior.

## Tests to Add

- API parser fixtures for activation, OTP, session, scan, refresh and errors;
  invalid JSON, stalled response body, 401/403/429 and partial sync responses.
- Activation expiry/reuse, OTP paste/resend, approval pending/revoked, local PIN
  lock/reset, restart/resume, token refresh and expiry state transitions.
- Event/gate context never changes during a pending scan; singleton/multiple
  assignments, shift start/end and event switching tested.
- Mock camera tests for repeated frames and confirmation; backend-assisted tests
  for duplicate admission, wrong event and included-item redemption.
- Offline package tamper/wrong key/expiry, queue durability, duplicate UUID retry,
  partial acknowledgments, conflict/quarantine and unsynced logout tests.
- Real Android devices: lower-memory phone, common Android versions, slow/no
  network, permission denial, battery saver, background/resume and signed update.
- If iOS distribution is later intended, add its signing, permissions, secure
  storage and real-device test plan separately; Android APK tests do not prove it.

## Release Checklist and Build Coordination

1. Laravel freezes contract fixtures and deploys compatible migrations/API.
2. Flutter implements the matching online activation/session flow.
3. Test two phones, separate assignments and replacement/revocation end-to-end.
4. Produce signed release APK, checksum and versioned release notes; confirm no
   development host, demo admission flow or credentials are shipped.
5. Pilot one real event with an operational fallback and monitored error rates.
6. Retire legacy broad access only after approved users/devices are migrated.
7. Enable offline only after both projects pass package/sync acceptance tests.

Release key management, hardware-backed storage behavior, real SMS delivery,
production server compatibility and gate throughput remain validation tasks,
not completed features. This change creates documentation only.
