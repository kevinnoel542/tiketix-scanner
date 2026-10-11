# TiketiX Flutter Scanner Documentation

Reviewed: 2026-09-30.

## Start here

This is the new Flutter gate-scanning app. It has an API client and screens,
but its visible sign-in button currently opens preview mode, not real login.
Do not use preview results to admit real attendees.

The Laravel TiketiX project already implements all 14 endpoints called by
this client, plus a batch synchronization endpoint that Flutter does not call.
The first job is integration and verification, not rebuilding the API.

Read in order:

1. [Project review](PROJECT_REVIEW.md): architecture, screens, and observed gaps.
2. [API contract](API_CONTRACT.md): current requests, responses, and proposed changes.
3. [Connection guide](CONNECTION_GUIDE.md): environment and first real-device test.
4. [Implementation tasks](IMPLEMENTATION_TASKS.md): work to check off as completed.

## Scope and evidence

This is a source-code review, not a certification of live scanning or security.
No app behavior, database, account, or backend endpoint was changed for this review.
No camera test, Flutter analysis/test run, or authenticated API test was performed.

Sources in this app:

- `lib/main.dart`, `lib/state/app_controller.dart`
- `lib/services/scanner_api.dart`, `lib/services/storage_service.dart`
- `lib/models/scanner_models.dart`, `lib/screens/`
- `test/widget_test.dart`, `pubspec.yaml`
- Android manifest and iOS `Runner/Info.plist`

Laravel source reviewed in the sibling `../../tiketiX` project:

- `routes/api.php`
- `app/Http/Controllers/Api/V1/ScannerController.php`
- `app/Http/Requests/Scanner/`
- `config/scanner.php`, `config/sanctum.php`

Items marked **current** describe inspected code. Items marked **proposed**
are not implemented by this documentation. Existing routes still need live tests.
