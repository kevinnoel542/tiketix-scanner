# Scanner Implementation Tasks

Reviewed 2026-09-30. A checked source-review item means inspected, not live-tested.
Leave implementation unchecked until code and acceptance tests both pass.

## 0. Discovery completed

- [x] Inspect Flutter architecture, services, models, and screen flows.
- [x] Map the 14 API calls to existing Laravel scanner routes.
- [x] Inspect existing server batch-sync endpoint and request validation.
- [x] Identify preview-only login, session clearing, and missing offline queue.
- [x] Create review, contract, connection guide, and task documentation.

## 1. Real online integration (first)

- [ ] Wire login form submission to `AppController.login` with entered credentials.
- [ ] Add form validation, password-safe errors, loading state, and duplicate-submit guard.
- [ ] Disable preview in release builds; make development preview unmistakable.
- [ ] Configure API_URL and test health from a real device.
- [ ] Restore saved token and revalidate session at startup.
- [ ] Restore selected event only after rechecking access.
- [ ] Retain both validate/check-in permissions and gate actions accordingly.
- [ ] Connect registration and approval/blocked screens to the real policy.
- [ ] Test account switching against device ownership rules.
- [ ] Verify real event list, selection, attendance, history, and progress.

Acceptance: real login, real device, real event, one valid scan/confirmation,
duplicate rejection, and matching server attendance. No demo data in the flow.

## 2. Contract and admission safety

- [ ] Align advertised bearer-token expiry with server enforcement.
- [ ] Verify account eligibility and token abilities server-side.
- [ ] Apply the chosen blocked-device policy to sensitive read endpoints.
- [ ] Verify ticket/payment/event eligibility before validation and mutation.
- [ ] Define multi-ticket order add-on ownership: shared or assigned per ticket.
- [ ] Standardize record UUID, public ticket number, and secret validation token.
- [ ] Implement public ticket-number lookup using its actual backend source.
- [ ] Parse and display verification fields and missing-info warnings.
- [ ] Parse/display selected add-on options and correct redemption action labels.
- [ ] Minimize token/attendee exposure in responses, logs, and diagnostics.
- [ ] Define statistics that distinguish eligible entries from other ticket states.
- [ ] Add persistent operation idempotency to check-in and test concurrent retries.
- [ ] Keep v1 compatibility for older clients or explicitly version breaking changes.

## 3. Mobile reliability

- [ ] Put camera stop/start failure handling inside guaranteed cleanup paths.
- [ ] Bound complete network response reads, not just initial connection/headers.
- [ ] Handle 429 backoff and field-specific validation feedback.
- [ ] Reject stale search/event responses; prevent repeat confirmation taps.
- [ ] Refresh progress and history after successful actions.
- [ ] Preserve safe-area navigation across target phone sizes.
- [ ] Test real Android/iPhone QR scanning, lifecycle, permissions, and torch.
- [ ] Decide whether shutter/image decoding fallback is needed after camera testing.
- [ ] Resolve `Attendee.fromJson` redundant null fallback and run Flutter analyzer.
- [ ] Decide native-only versus web support; remove unsupported web assumptions.
- [ ] Add HTTP, widget, and end-to-end tests beyond the five existing model tests.

## 4. Optional detail and device operations

- [ ] Decide whether to add a dedicated read-only ticket detail endpoint.
- [ ] Audit existing organizer device controls before adding approve/block/reassign APIs.
- [ ] Add heartbeat only if device monitoring needs it.

## 5. Offline release (not part of initial online integration)

- [ ] Approve a policy for disconnected gates and cross-device duplicate risk.
- [ ] Design minimal versioned manifests, expiry, revocation, and authorized downloads.
- [ ] Add encrypted local queue with stable operation IDs and original timestamps.
- [ ] Extend batch sync with per-operation acknowledgment and conflict resolution.
- [ ] Separate local unsent counts from server sync statistics.
- [ ] Test reconnection, partial failure, process death, repeated batches, and logout.
- [ ] Obtain operational sign-off before permitting offline admissions.

## Release evidence

- [ ] Record Flutter analyze/test results and backend feature-test results.
- [ ] Record tested OS/device/app versions without credentials or attendee secrets.
- [ ] Verify wrong-event, blocked-device, unpaid/refunded, duplicate, and timeout tests.
- [ ] Confirm no hardcoded demo admission path is reachable in release.
- [ ] Confirm organizer attendance and scanner history agree after the test event.
