# Scanner API Contract and Required Changes

## Decision

Reuse `/api/v1/scanner`. All routes below already exist in Laravel source.
Do not create a second authentication or check-in API just because Flutter is new.
No new endpoint is strictly required for the basic online screens; fixes to
authentication wiring and contract consistency come first.

## Transport

Set Flutter `API_URL` to the server origin, without `/api` at the end. The client
adds `/api/v1/scanner` itself. Use HTTPS in production.

Headers currently sent:

```http
Accept: application/json
Content-Type: application/json
Authorization: Bearer <access_token>
X-Request-ID: <new request identifier>
```

Health/login omit Authorization. `X-Request-ID` is currently generated afresh
for every request: it is not an idempotency key. Never embed server API secrets
or payment-provider credentials in Flutter.

## Existing endpoint inventory

All paths below are relative to `/api/v1/scanner`.

| Method and path | Request | Current response used by Flutter |
| --- | --- | --- |
| GET `/health` | Public | `status`, `service`, `timestamp` |
| POST `/auth/login` | `email`, `password` | `access_token`; server also returns `token_type`, `expires_at`, `user` |
| POST `/auth/logout` | Bearer token | `status: LOGGED_OUT`, `message` |
| GET `/session/me` | Query `device_id` | `user`, `device_status`, `event_access`, `permissions`, optional `device` |
| POST `/devices/register` | `device_id`, `device_name`, `platform`, optional `app_version` | `status`, `device` |
| GET `/events` | Bearer token | `{ "events": [...] }` |
| GET `/events/{event}` | Integer event ID | `{ "event": {...}, "stats": {...} }` |
| POST `/validate` | Scan body below | Scan result; no admission mutation |
| POST `/check-in` | Same scan body | Scan result; admission or selected entitlement mutation |
| GET `/lookup` | `event_id`, `query` | `{ "results": [...] }`, maximum 50, no pagination |
| GET `/attendees` | `event_id`, optional `search`, `checked_in`, `page`, `per_page` | `{ "data": [...], "meta": {...} }` |
| GET `/history` | `event_id`, optional `limit` (1-200) | `{ "items": [...] }`, current operator's history |
| GET `/stats` | `event_id` | `total`, `checked_in`, `pending`, `duplicates`, `invalid_attempts` |
| GET `/sync/status` | `event_id` | `pending_count`, `failed_count`, `last_successful_sync_at` |
| POST `/sync-checkins` | `device_id`, `checkins` array (1-200) | `status`, `summary`, `results`; not called by Flutter yet |

Laravel routes use Sanctum and scanner throttling except public health; login
is throttled without Sanctum. Scanner roles in organizer membership, or the
global-scanner exception, govern event access. Do not infer access from a user
email or an event ID supplied by the phone.

## Login and device sequence

1. POST login and store `access_token` in secure storage.
2. GET session with the persistent installation `device_id`.
3. If unregistered, POST device registration and GET session again.
4. Only allow scanning with approved device, event access, and appropriate
   permissions. Pending/blocked must not be bypassable through a direct POST.
5. GET events and select one before validating tickets.

Registration fields: device ID maximum 100 characters; name maximum 150;
platform maximum 20; version maximum 50. Flutter currently sends `android` or
`ios` and hardcodes app version `1.0.0`. The server rejects a device ID already
registered to another user with `409 DEVICE_ALREADY_REGISTERED`. Logging out
does not erase installation ID; changing operators needs an explicit device
ownership/reassignment policy, not a random-ID workaround.

Illustrative session response matching current keys:

```json
{
  "user": {"id": 80, "name": "Gate Operator", "email": "gate@example.test"},
  "device_status": "approved",
  "event_access": true,
  "permissions": ["scan.validate", "scan.checkin"]
}
```

## Events and attendee lists

Event fields consumed: integer `id`, `title`, `venue`, `city`, `status`, ISO-8601
`start_at`/`end_at`, and `stats: {total, checked_in, pending}`. Detail stats are
outside `event`; the Flutter API client merges them into its event model.

The current list filters statuses `published`, `sales_paused`, `sold_out`; it
does not explicitly exclude finished dates. Decide the gate's active/archive
policy rather than copying the public storefront filter blindly.

Attendee fields consumed: `ticket_id` (or legacy `ticketId`), optional `token`,
`name`, `email`, `phone`, `company`, `role` (ticket category), `booking_code`,
`checked_in`, `checked_in_at`. List and lookup shapes differ today: lookup
includes booking code but not phone; attendee listing includes phone but not
booking code. Unify deliberately, with privacy controls.

Pagination metadata: `current_page`, `last_page`, `per_page`, `total`.
Flutter requests 50 per page; the server allows 1-100.

## Validation and check-in

Send either `token` or UUID `ticket_id`, not a customer name or a price:

```json
{
  "event_id": 15,
  "device_id": "flutter-installation-id",
  "token": "<ticket-validation-token>"
}
```

For included-item redemption, keep the same ticket code and add:

```json
{
  "event_id": 15,
  "device_id": "flutter-installation-id",
  "token": "<ticket-validation-token>",
  "entitlement_id": "<entitlement-uuid>"
}
```

The server must resolve that entitlement against the authorized event and
ticket/order relationship. A phone-supplied entitlement ID is not authorization.

Current business statuses:

| Status | Meaning | App action |
| --- | --- | --- |
| `PENDING_CONFIRMATION` | Valid candidate; not admitted/redeemed yet | Show identity and explicit confirmation |
| `CHECKED_IN` | Admission or redemption recorded | Success; refresh local views |
| `ALREADY_CHECKED_IN` | Previously admitted/redeemed | Warning; never count as a new entry |
| `INVALID_TOKEN` | No usable matching record for selected event | Reject; offer authorized lookup |

These business results are JSON success responses in the inspected controller;
do not treat HTTP 200 alone as admission success.

Response structure:

```json
{
  "status": "PENDING_CONFIRMATION",
  "severity": "info",
  "message": "Ticket valid. Confirm check-in.",
  "item_type": "ticket",
  "attendee": {
    "name": "Example Guest",
    "email": "guest@example.test",
    "phone": null,
    "company": null,
    "role": "VIP",
    "ticketId": "<legacy field currently containing token or record ID>"
  },
  "verification": {
    "ticket_record_id": "<ticket-uuid>",
    "ticket_code": "<current validation code>",
    "booking_reference": "<payment reference>",
    "ticket_status": "active",
    "payment_status": "paid",
    "event_id": 15,
    "missing_fields": ["Phone number"]
  },
  "event_pass": {
    "ticket_id": "<ticket-uuid>",
    "admission": {"label": "VIP", "status": "active", "redeemed_at": null},
    "included_items": []
  },
  "checked_in_at": null
}
```

This is an illustrative shape, not a real token or attendee. Flutter currently
ignores `verification`. Included items carry `id`, `name`, `category`,
`selected_option`, `staff_redemption`, `status`, `redeemed_at`.

## Errors

Scanner-specific validation/access errors use:

```json
{"error":{"code":"DEVICE_BLOCKED","message":"This device is blocked and cannot scan tickets.","details":{}}}
```

- 401: expired/missing token or invalid credentials; clear session as appropriate.
- 403: no event access or unapproved/blocked device; do not retry as admission.
- 409: device belongs to another account.
- 422: invalid fields; show actionable feedback.
- 429: respect `Retry-After` and limit retries.
- 5xx/timeouts: outcome may be unknown after a write; reconcile before admitting again.

Some ordinary Laravel validation/authentication errors use top-level `message`
and `errors` instead of the scanner envelope. The client has a message fallback,
but does not expose field errors consistently. Standardize without breaking v1.

## Synchronization: current versus proposed

Current batch body:

```json
{
  "device_id": "flutter-installation-id",
  "checkins": [
    {"event_id": 15, "token": "<ticket-validation-token>"}
  ]
}
```

Each item may instead use `ticket_id`, and may include `entitlement_id`.
Current response is `SYNC_COMPLETED` with `summary` counters and per-item scan
results. This is not a complete offline protocol: there is no stable operation
ID, manifest, local queue acknowledgment, or original scan timestamp contract.

## What to add or change

### Required changes to existing endpoints

- Enforce token expiry, account eligibility, token abilities, approved device
  policy, event scope, ticket/payment status, and allowed redemption rules.
- Add safe public `ticket_number`; keep legacy fields temporarily for older clients.
- Make `verification` and entitlement options usable in the Flutter result model.
- Add an `Idempotency-Key` contract to `/check-in`: persist one UUID per user
  action, reuse it on retry, scope to authenticated actor/device, store the
  request hash and original response atomically with the write. Reject key reuse
  with a different body. A new legitimate action gets a new key.
- Extend `/sync-checkins` with stable `operation_id` values and explicit per-item
  acknowledgments before enabling offline uploads. Define retention and conflict policy.
- Make search and totals consistent; do not label unpaid/cancelled tickets as
  pending admissions without an explicit counting policy.

### Proposed new routes only when their feature is approved

| Proposed endpoint | Why | Priority |
| --- | --- | --- |
| GET `/tickets/{ticket}/details?event_id=...` | Authorized read-only attendee/pass details without creating a validation audit on every tap | Useful next; existing validate can serve first release |
| POST `/devices/heartbeat` | Device last seen, app version, and operational status outside scanning | Later device operations; not required for online scanning |
| GET `/events/{event}/manifest?cursor=...` | Versioned minimal offline eligibility data with expiry/revocations | Only for an explicitly designed offline release |
| GET `/operations/{operation_id}` | Recover a timed-out mutation outcome | Optional if replaying an idempotent check-in already resolves it |

All proposed routes must use authenticated event/device authorization. A manifest
requires privacy minimization, protected local storage, expiry, revoked-ticket
deltas, and deletion on logout. Independent disconnected gates cannot guarantee
global duplicate prevention; do not promise that they can.

Device approve/block/reassign operations belong in the organizer/admin control
plane. Audit existing web controls before adding duplicate APIs, and never give
scanner tokens permission to approve themselves.
