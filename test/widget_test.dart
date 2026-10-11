import 'package:flutter_test/flutter_test.dart';
import 'package:ticketx_scanner/models/scanner_models.dart';

void main() {
  test('ScannerEvent parses event statistics', () {
    final event = ScannerEvent.fromJson({
      'id': 12,
      'title': 'Launch Night',
      'stats': {'checked_in': 42, 'total': 80, 'pending': 38},
    });

    expect(event.id, 12);
    expect(event.title, 'Launch Night');
    expect(event.checkedIn, 42);
    expect(event.total, 80);
  });

  test('EventStats parses check-in counts', () {
    final stats = EventStats.fromJson({
      'checked_in': 35,
      'total': 50,
      'pending': 15,
    });

    expect(stats.checkedIn, 35);
    expect(stats.total, 50);
    expect(stats.pending, 15);
  });

  test('SessionInfo requires approval, access and validation permission', () {
    final approved = SessionInfo.fromJson({
      'device_status': 'approved',
      'event_access': true,
      'permissions': ['scan.validate', 'scan.checkin'],
      'user': {'email': 'gate@example.com'},
    });
    final pending = SessionInfo.fromJson({
      'device_status': 'pending',
      'event_access': true,
      'permissions': ['scan.validate'],
    });

    expect(approved.canScan, isTrue);
    expect(approved.email, 'gate@example.com');
    expect(pending.canScan, isFalse);
  });

  test('Event pass exposes only redeemable staff entitlements', () {
    final result = ScanResult.fromJson({
      'status': 'PENDING_CONFIRMATION',
      'severity': 'info',
      'message': 'Valid',
      'event_pass': {
        'included_items': [
          {
            'id': 'parking-1',
            'name': 'Parking',
            'status': 'active',
            'staff_redemption': true,
          },
          {
            'id': 'meal-1',
            'name': 'Meal',
            'status': 'redeemed',
            'staff_redemption': true,
            'redeemed_at': '2026-09-29T10:00:00+03:00',
          },
        ],
      },
    });

    expect(result.eventPass!.items.first.canRedeem, isTrue);
    expect(result.eventPass!.items.last.canRedeem, isFalse);
  });

  test('Attendee prefers token for validation', () {
    final attendee = Attendee.fromJson({
      'name': 'Kelvin',
      'ticket_id': '019fa79c-10b2-734d-a903-526def753150',
      'token': 'tkt_abc1234567890defghij',
    });

    expect(attendee.scanCode, 'tkt_abc1234567890defghij');
  });
}
