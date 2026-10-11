class ScannerEvent {
  const ScannerEvent({
    required this.id,
    required this.title,
    this.venue,
    this.city,
    this.status,
    this.startAt,
    this.endAt,
    this.total = 0,
    this.checkedIn = 0,
    this.pending = 0,
  });

  final int id;
  final String title;
  final String? venue;
  final String? city;
  final String? status;
  final DateTime? startAt;
  final DateTime? endAt;
  final int total;
  final int checkedIn;
  final int pending;

  factory ScannerEvent.fromJson(Map<String, dynamic> json) {
    final stats = _map(json['stats']);
    return ScannerEvent(
      id: _integer(json['id']),
      title: json['title']?.toString() ?? 'Untitled event',
      venue: _optionalString(json['venue']),
      city: _optionalString(json['city']),
      status: _optionalString(json['status']),
      startAt: DateTime.tryParse(json['start_at']?.toString() ?? ''),
      endAt: DateTime.tryParse(json['end_at']?.toString() ?? ''),
      total: _integer(stats['total']),
      checkedIn: _integer(stats['checked_in']),
      pending: _integer(stats['pending']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'venue': venue,
    'city': city,
    'status': status,
    'start_at': startAt?.toIso8601String(),
    'end_at': endAt?.toIso8601String(),
    'stats': {'total': total, 'checked_in': checkedIn, 'pending': pending},
  };
}

class SessionInfo {
  const SessionInfo({
    required this.deviceStatus,
    required this.eventAccess,
    required this.permissions,
    this.email,
    this.name,
  });

  final String deviceStatus;
  final bool eventAccess;
  final List<String> permissions;
  final String? email;
  final String? name;

  bool get canScan =>
      deviceStatus == 'approved' &&
      eventAccess &&
      permissions.contains('scan.validate');

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final user = _map(json['user']);
    return SessionInfo(
      deviceStatus: json['device_status']?.toString() ?? 'unregistered',
      eventAccess: json['event_access'] == true || json['event_access'] == 1,
      permissions: json['permissions'] is List
          ? (json['permissions'] as List)
                .map((item) => item.toString())
                .toList()
          : const [],
      email: _optionalString(user['email']),
      name: _optionalString(user['name']),
    );
  }
}

class Attendee {
  const Attendee({
    required this.id,
    required this.name,
    required this.ticketId,
    this.token,
    this.email,
    this.phone,
    this.company,
    this.role,
    this.bookingCode,
    this.checkedIn = false,
    this.checkedInAt,
  });

  final String id;
  final String name;
  final String ticketId;
  final String? token;
  final String? email;
  final String? phone;
  final String? company;
  final String? role;
  final String? bookingCode;
  final bool checkedIn;
  final String? checkedInAt;

  String get scanCode => token?.isNotEmpty == true ? token! : ticketId;

  factory Attendee.fromJson(Map<String, dynamic> json) {
    final ticketId = (json['ticket_id'] ?? json['ticketId'] ?? '').toString();
    return Attendee(
      id: (json['id'] ?? ticketId ?? json['token'] ?? '').toString(),
      name: json['name']?.toString() ?? 'Unknown guest',
      ticketId: ticketId,
      token: _optionalString(json['token']),
      email: _optionalString(json['email']),
      phone: _optionalString(json['phone']),
      company: _optionalString(json['company']),
      role: _optionalString(json['role']),
      bookingCode: _optionalString(json['booking_code']),
      checkedIn: json['checked_in'] == true || json['checked_in'] == 1,
      checkedInAt: _optionalString(json['checked_in_at']),
    );
  }
}

class EventPass {
  const EventPass({this.admission, this.items = const []});

  final Entitlement? admission;
  final List<Entitlement> items;

  factory EventPass.fromJson(Map<String, dynamic> json) => EventPass(
    admission: json['admission'] is Map
        ? Entitlement.fromJson(_map(json['admission']), isAdmission: true)
        : null,
    items: json['included_items'] is List
        ? (json['included_items'] as List)
              .whereType<Map>()
              .map((item) => Entitlement.fromJson(_map(item)))
              .toList()
        : const [],
  );
}

class Entitlement {
  const Entitlement({
    this.id,
    required this.name,
    required this.status,
    this.category,
    this.redeemedAt,
    this.staffRedemption = false,
    this.isAdmission = false,
  });

  final String? id;
  final String name;
  final String status;
  final String? category;
  final String? redeemedAt;
  final bool staffRedemption;
  final bool isAdmission;

  bool get canRedeem =>
      !isAdmission &&
      staffRedemption &&
      status == 'active' &&
      redeemedAt == null;

  factory Entitlement.fromJson(
    Map<String, dynamic> json, {
    bool isAdmission = false,
  }) => Entitlement(
    id: _optionalString(json['id']),
    name:
        json['name']?.toString() ??
        json['label']?.toString() ??
        (isAdmission ? 'Event admission' : 'Included item'),
    status: json['status']?.toString() ?? 'unknown',
    category: _optionalString(json['category']),
    redeemedAt: _optionalString(json['redeemed_at']),
    staffRedemption:
        json['staff_redemption'] == true || json['staff_redemption'] == 1,
    isAdmission: isAdmission,
  );
}

class ScanResult {
  const ScanResult({
    required this.status,
    required this.message,
    required this.severity,
    this.attendee,
    this.eventPass,
    this.itemType,
    this.checkedInAt,
  });

  final String status;
  final String message;
  final String severity;
  final Attendee? attendee;
  final EventPass? eventPass;
  final String? itemType;
  final String? checkedInAt;

  bool get canConfirm => status == 'PENDING_CONFIRMATION';
  bool get isSuccess => status == 'CHECKED_IN';

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
    status: json['status']?.toString() ?? 'NETWORK_ERROR',
    message: json['message']?.toString() ?? 'Unexpected scanner response.',
    severity: json['severity']?.toString() ?? 'info',
    attendee: json['attendee'] is Map
        ? Attendee.fromJson(_map(json['attendee']))
        : null,
    eventPass: json['event_pass'] is Map
        ? EventPass.fromJson(_map(json['event_pass']))
        : null,
    itemType: _optionalString(json['item_type']),
    checkedInAt: _optionalString(json['checked_in_at']),
  );
}

class EventStats {
  const EventStats({
    this.total = 0,
    this.checkedIn = 0,
    this.pending = 0,
    this.duplicates = 0,
    this.invalidAttempts = 0,
  });

  final int total;
  final int checkedIn;
  final int pending;
  final int duplicates;
  final int invalidAttempts;

  factory EventStats.fromJson(Map<String, dynamic> json) => EventStats(
    total: _integer(json['total']),
    checkedIn: _integer(json['checked_in']),
    pending: _integer(json['pending']),
    duplicates: _integer(json['duplicates']),
    invalidAttempts: _integer(json['invalid_attempts']),
  );
}

class AttendeePage {
  const AttendeePage({
    required this.items,
    required this.page,
    required this.lastPage,
    required this.total,
  });

  final List<Attendee> items;
  final int page;
  final int lastPage;
  final int total;

  factory AttendeePage.fromJson(Map<String, dynamic> json) {
    final source = json['data'] is List ? json['data'] as List : const [];
    final meta = _map(json['meta']);
    return AttendeePage(
      items: source
          .whereType<Map>()
          .map((item) => Attendee.fromJson(_map(item)))
          .toList(),
      page: _integer(meta['current_page'], fallback: 1),
      lastPage: _integer(meta['last_page'], fallback: 1),
      total: _integer(meta['total'], fallback: source.length),
    );
  }
}

class ScanHistoryItem {
  const ScanHistoryItem({
    required this.id,
    required this.action,
    required this.status,
    required this.severity,
    required this.message,
    required this.timestamp,
    required this.syncStatus,
  });

  final String id;
  final String action;
  final String status;
  final String severity;
  final String message;
  final DateTime? timestamp;
  final String syncStatus;

  factory ScanHistoryItem.fromJson(Map<String, dynamic> json) =>
      ScanHistoryItem(
        id: json['id']?.toString() ?? '',
        action: json['action']?.toString() ?? 'scan',
        status: json['status']?.toString() ?? 'UNKNOWN',
        severity: json['severity']?.toString() ?? 'info',
        message: json['message']?.toString() ?? '',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? ''),
        syncStatus: json['sync_status']?.toString() ?? 'online',
      );
}

class SyncStatus {
  const SyncStatus({
    this.pendingCount = 0,
    this.failedCount = 0,
    this.lastSuccessfulSyncAt,
  });

  final int pendingCount;
  final int failedCount;
  final DateTime? lastSuccessfulSyncAt;

  factory SyncStatus.fromJson(Map<String, dynamic> json) => SyncStatus(
    pendingCount: _integer(json['pending_count']),
    failedCount: _integer(json['failed_count']),
    lastSuccessfulSyncAt: DateTime.tryParse(
      json['last_successful_sync_at']?.toString() ?? '',
    ),
  );
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int _integer(Object? value, {int fallback = 0}) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

String? _optionalString(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}
