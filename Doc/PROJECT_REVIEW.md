# Project Review

## Stack and ownership

- Flutter/Dart; `pubspec.yaml` declares Dart `^3.13.3`.
- Material widgets, custom green/white theme, `ChangeNotifier` application state.
- `http` handles JSON requests; `flutter_secure_storage` stores the bearer token.
- `shared_preferences` stores device identity, selected event, email, and preferences.
- `mobile_scanner` handles camera decoding; the app configures QR codes only.
- `intl` is present for formatting.
- Android, iOS, and web scaffolding exists. Web support is not established:
  the API client directly imports `dart:io` and uses `Platform.operatingSystem`.

Laravel owns authorization, ticket validity, check-in state, add-on redemption,
and audit records. Flutter must not decide that a ticket is valid from its QR
contents alone.

## Code map

| File | Responsibility |
| --- | --- |
| `lib/main.dart` | Startup and screens for loading, signed out, blocked, no access, errors, and ready |
| `lib/state/app_controller.dart` | Session/device gates, active event, preferences, preview state |
| `lib/services/scanner_api.dart` | API URL, bearer headers, JSON parsing, requests and error translation |
| `lib/services/storage_service.dart` | Secure token and local preferences |
| `lib/models/scanner_models.dart` | Event, session, attendee, pass, entitlement, result, history, stats models |
| `lib/screens/shell_screen.dart` | Scan, Events, Attendees, Progress, Settings tabs |
| `lib/screens/scan_screen.dart` | Live QR detection, manual input, result sheet, confirmation and redemption |
| `lib/screens/events_screen.dart` | Event list, detail sheet, selecting the active event |
| `lib/screens/attendees_screen.dart` | Paginated list, lookup, attendee validation and admission |
| `lib/screens/progress_screen.dart` | Event statistics and server sync-status display |
| `lib/screens/history_screen.dart` | Recent scanner history, accessed from Settings |
| `lib/screens/settings_screen.dart` | Operator/device information, sound, haptics, diagnostics, logout |

## Current user journey

1. Startup runs `initialize()`, which deletes the saved session and active event.
2. Login displays email and password fields.
3. Both password submission and the sign-in button call `enterPreviewMode()`.
4. Preview supplies a sample event and simulated attendee/scan outcomes.
5. The real `AppController.login()` and API login method exist, but this screen
   does not call them.

The intended real journey is login -> session check -> register/approve device
-> choose authorized event -> validate QR -> inspect attendee -> confirm admission
or redeem a specific included item -> refresh stats/history.

## What already exists

- Camera QR detection and torch control; camera stop/resume handling for tab and
  app lifecycle changes.
- Manual token/URL/UUID input; URL normalization recognizes `/t/{token}` and a
  `token` query parameter.
- A two-step validate/confirm flow; validation itself does not admit a guest.
- Included-item redemption through the same ticket, using `entitlement_id`.
- Token cleanup on a server 401 and local logout cleanup even if the server fails.
- Attendee listing with pagination; lookup uses a separate search route.
- Five model unit tests in `test/widget_test.dart`; these are not UI or camera tests.
- Camera usage permission entries in Android and iOS source.

## Gaps to fix before live use

### Critical: preview is presented as sign-in

`login_screen.dart` ignores the entered credentials and opens preview mode.
Wire the form to `controller.login(email, password)`, with validation, loading,
and error handling. Remove preview from release builds or expose it as an
explicitly labeled development-only action. Demo success must never look like
a real server check-in.

### Session restoration is disabled

`AppController.initialize()` calls `storage.clearSession()` on every launch.
Restore the secure token, verify it with `/session/me`, and only then restore
an event that remains accessible. Clear session data on real expiration/logout,
not ordinary startup.

### Verification information is lost

Laravel sends `verification` with payment status, ticket status, booking
reference, event ID, and missing identity fields. `ScanResult` does not parse it.
Add a typed model and show relevant details without exposing validation secrets.
Also parse add-on `selected_option` so staff can distinguish sizes/options.

### Inconsistent ticket identifiers

List responses use `ticket_id` for the record UUID and `token` separately.
Scan responses use camel-case `attendee.ticketId`, currently filled with the
token when present. The app accepts that field as `ticketId` and may display it.
Standardize the contract to separate `ticket_id`, public `ticket_number`, and
the secret used for validation. Do not silently break the older scanner client.

### No actual offline queue

There is no durable local check-in queue, offline manifest, retry worker, or
Flutter `sync-checkins` method. Progress only reads server sync status.
The server currently reports `pending_count: 0`; this cannot represent work
waiting on a disconnected phone. Treat the first release as online-only.

### Confirmation and permission details

- Session entry checks `scan.validate`; the UI does not retain separate
  `scan.checkin` capability for confirmation controls.
- The result sheet labels confirmation as admission even for standalone
  legacy add-on results. Use `item_type` to label redemption correctly.
- `scanner.stop()` runs before the scan operation's `try/finally`; a camera
  failure there can leave `busy` set. Test and harden the camera lifecycle.
- The request timeout wraps `client.send`, not the entire streamed response
  read. Bound the complete request/response duration.
- Lookup search stops at 50 results and the app treats that as the full total.
  Use paginated search or clearly indicate the limit.
- Event and search requests can finish after a newer selection/search. Add
  stale-response guards and refresh progress after successful check-in.
- There is no shutter/image-analysis fallback in this implementation. Do not
  assume the earlier scanner's capture workflow was carried over.

## Backend findings needing verification/hardening

1. **Token expiry:** login reports an expiry using the scanner configuration,
   but `createToken()` is called without an explicit expiry and inspected
   `config/sanctum.php` has `expiration => null`. Align advertised and enforced
   expiry and test expired tokens. A timestamp in JSON alone is not enforcement.
2. **Device approval:** the source default is `approved`, not manual approval.
   Choose the actual rollout policy; the current environment was not inspected.
3. **Read access:** validate/check-in require approved devices. Attendee, lookup,
   stats, history, and event reads check event access but not device approval.
   Decide whether blocked devices should also lose access to attendee information.
4. **Payment and event eligibility:** ticket resolution requires active status,
   but the inspected scanner path does not explicitly require a paid order or
   an allowed event entry window. Verify upstream invariants and enforce the
   admission policy server-side, including legitimate complimentary tickets.
5. **Order-level add-ons:** included items are loaded from the entire order.
   Every ticket in a multi-ticket order may see the same order entitlements.
   Decide whether items are shared per order or assigned per admission unit;
   enforce that decision and explain it to staff.
6. **Sensitive fields:** lookup/list/history currently return validation tokens,
   and scan audits store tokens. Minimize secret exposure and retention; restrict
   attendee contact details by role. Do not put raw payloads in mobile diagnostics.
7. **Retries:** database transactions and row locking prevent a second redemption,
   but a repeated request returns `ALREADY_CHECKED_IN`, not a replay of the
   original success. Add durable operation idempotency for ambiguous timeouts.
8. **Public lookup:** lookup searches internal IDs/tokens/payment references,
   but has no explicit short public ticket-number lookup shown here. Define the
   real public-number source before promising `TX-...` search.

These are findings from the inspected paths, not claims that all possible
upstream safeguards have been audited.
