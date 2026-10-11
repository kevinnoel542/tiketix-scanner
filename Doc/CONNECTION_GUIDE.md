# Connection and Verification Guide

## Prerequisites

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`.
- Android toolchain or macOS/Xcode for an iOS build.
- Running TiketiX Laravel backend, database, and scanner routes.
- A real authorized scanner/organizer membership and test event/ticket.
- Fix the preview-only sign-in path first. Setting API_URL alone does not fix it.

## Configure Flutter

Run from this app root:

```bash
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=API_URL=https://YOUR_TIKETIX_HOST
```

`YOUR_TIKETIX_HOST` is a placeholder. Supply an origin, not a path ending in
`/api/v1/scanner`. API_URL is compiled into the app; rebuild after changing it.
These commands are proposed verification steps, not commands already run in
this documentation review.

## Test on a phone using the same Wi-Fi

Run Laravel listening on a reachable interface, using its actual free port:

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

Then point Flutter at the computer's actual LAN address, for example:

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:8000
```

The address above is illustrative. `0.0.0.0` is a server bind address, not the
address to enter on a phone. `localhost` on the phone means the phone itself.
Allow the port through the local firewall; check that Wi-Fi client isolation
is not blocking traffic. Prefer a trusted HTTPS development endpoint. The
inspected manifests do not establish a local HTTP exception; add narrowly
scoped debug-only networking settings if required by the target platform.
Do not globally disable transport security in a release build.

Test reachability without credentials:

```bash
curl -H 'Accept: application/json' https://YOUR_TIKETIX_HOST/api/v1/scanner/health
```

Expected shape: `status: UP`, `service: scanner-api`, `timestamp`.
Do not paste passwords or bearer tokens into shared terminal logs or screenshots.

## First real-device acceptance test

1. Ensure release/test mode uses real login, not the sample Kuku Festival data.
2. Sign in with a test account; verify server identity and event membership.
3. Register the device; verify pending/approved/blocked behavior according to policy.
4. Select the actual test event. Confirm its name, date, and ID match Laravel.
5. Scan an unused paid/eligible test ticket: review full name, ticket category,
   public ticket number, eligibility, and included items before confirming.
6. Confirm entry once; verify database state, audit history, and progress totals.
7. Scan it again: display duplicate warning and do not increment attendance.
8. Redeem one included item using the same ticket QR. Confirm other items and
   admission state remain independent. Repeat redemption and reject the duplicate.
9. Test wrong-event, inactive/refunded, malformed, missing, and expired-session cases.
10. Test two devices confirming simultaneously and a lost response after success.
11. Test device block and membership removal while the app is open.
12. Restart the app; verify intended session/event restoration, then logout cleanup.
13. Test camera permission denial, tab switching, background/resume, and torch.

Until offline support is explicitly built, network failure must not produce a
green success message or claim a ticket has been synchronized.

## Contract test coverage to add

- Flutter HTTP tests for every success envelope and 401/403/409/422/429/5xx cases.
- Login widget test proving entered credentials call real authentication.
- Models for verification, safe identifiers, and selected add-on options.
- Full-body timeout, retry backoff, session expiry, stale searches/event changes.
- Laravel scanner feature tests for role/event/device isolation and concurrent writes.
- Release checks proving preview cannot admit a real attendee.

Run database tests only against an isolated test database. Never use a production
database or destructive schema reset to verify the scanner integration.
