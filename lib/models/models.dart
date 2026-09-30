import 'package:latlong2/latlong.dart';

import '../core/config.dart';

double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
double? _dn(Object? v) => v == null ? null : _d(v);
int? _in(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
DateTime? _dt(Object? v) => v == null ? null : DateTime.tryParse('$v');
List<Map<String, dynamic>> _list(Object? v) => v is List ? v.cast<Map<String, dynamic>>() : const [];
LatLng? _point(Object? lat, Object? lng) {
  final a = _dn(lat), b = _dn(lng);
  return a != null && b != null ? LatLng(a, b) : null;
}

enum UserRole { driver, vendor, other }

class User {
  User({required this.id, required this.name, required this.phone, required this.role, this.avatar, this.driver, this.raw = const {}});

  final int id;
  final String name;
  final String phone;
  final UserRole role;
  final String? avatar;
  final DriverProfile? driver;

  /// نحتفظ بالـ JSON كامل لنخزنه محليًا كما هو.
  final Map<String, dynamic> raw;

  bool get isDriver => role == UserRole.driver;
  bool get isVendor => role == UserRole.vendor;

  /// نفس منطق needs_profile في السيرفر: الإدارة لم تكمل بيانات السائق أو لم تربط التاجر بمتجر.
  bool get needsProfile => switch (role) {
        UserRole.driver => driver == null,
        UserRole.vendor => (raw['stores'] as List?)?.isEmpty ?? true,
        UserRole.other => true,
      };

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'],
        name: j['name'] ?? '',
        phone: j['phone'] ?? '',
        role: switch (j['role']) {
          'driver' => UserRole.driver,
          'vendor' => UserRole.vendor,
          _ => UserRole.other,
        },
        avatar: fixMediaUrl(j['avatar']),
        driver: j['driver'] is Map ? DriverProfile.fromJson((j['driver'] as Map).cast<String, dynamic>()) : null,
        raw: j,
      );

  Map<String, dynamic> toJson() => raw;
}

enum ApprovalStatus {
  pending('قيد المراجعة'),
  approved('معتمد'),
  rejected('مرفوض'),
  suspended('موقوف');

  const ApprovalStatus(this.label);
  final String label;

  static ApprovalStatus parse(String? s) =>
      ApprovalStatus.values.firstWhere((e) => e.name == s, orElse: () => pending);
}

enum VehicleType {
  motorcycle('موتوسيكل'),
  bicycle('عجلة'),
  car('سيارة'),
  tuktuk('توك توك');

  const VehicleType(this.label);
  final String label;

  static VehicleType? parse(String? s) => VehicleType.values.where((e) => e.name == s).firstOrNull;
}

enum DocumentType {
  nationalIdFront('national_id_front', 'البطاقة (وجه)'),
  nationalIdBack('national_id_back', 'البطاقة (ظهر)'),
  drivingLicense('driving_license', 'رخصة القيادة'),
  vehicleLicense('vehicle_license', 'رخصة المركبة'),
  personalPhoto('personal_photo', 'صورة شخصية');

  const DocumentType(this.key, this.label);
  final String key;
  final String label;
}

class DriverDocument {
  DriverDocument({required this.type, this.url, required this.status, this.notes});

  final String type;
  final String? url;
  final String status;
  final String? notes;

  factory DriverDocument.fromJson(Map<String, dynamic> j) =>
      DriverDocument(type: j['type'] ?? '', url: fixMediaUrl(j['url']), status: j['status'] ?? 'pending', notes: j['notes']);
}

class DriverProfile {
  DriverProfile({
    required this.id,
    this.vehicleType,
    this.vehiclePlate,
    this.nationalId,
    required this.approvalStatus,
    this.rejectionReason,
    required this.isOnline,
    required this.cashInHand,
    required this.cashLimit,
    required this.rating,
    required this.documents,
  });

  final int id;
  final VehicleType? vehicleType;
  final String? vehiclePlate;
  final String? nationalId;
  final ApprovalStatus approvalStatus;
  final String? rejectionReason;
  final bool isOnline;
  final double cashInHand;
  final double cashLimit;
  final double rating;
  final List<DriverDocument> documents;

  bool get isApproved => approvalStatus == ApprovalStatus.approved;

  DriverDocument? document(DocumentType t) => documents.where((d) => d.type == t.key).firstOrNull;

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        id: j['id'],
        vehicleType: VehicleType.parse(j['vehicle_type']),
        vehiclePlate: j['vehicle_plate'],
        nationalId: j['national_id'],
        approvalStatus: ApprovalStatus.parse(j['approval_status']),
        rejectionReason: j['rejection_reason'],
        isOnline: j['is_online'] == true,
        cashInHand: _d(j['cash_in_hand']),
        cashLimit: _d(j['cash_limit']),
        rating: _d(j['rating']),
        documents: _list(j['documents']).map(DriverDocument.fromJson).toList(),
      );
}

/// عرض توصيل مفتوح للسائق.
class Offer {
  Offer({
    required this.id,
    required this.expiresAt,
    required this.secondsLeft,
    this.distanceToStoreKm,
    this.deliveryDistanceKm,
    required this.earning,
    required this.collectAmount,
    required this.storeName,
    this.storeAddress,
    this.storePoint,
    this.deliveryPoint,
  });

  final int id;
  final DateTime expiresAt;
  final int secondsLeft;
  final double? distanceToStoreKm;
  final double? deliveryDistanceKm;
  final double earning;
  final double collectAmount;
  final String storeName;
  final String? storeAddress;
  final LatLng? storePoint;
  final LatLng? deliveryPoint;

  factory Offer.fromJson(Map<String, dynamic> j) {
    final store = (j['store'] as Map?)?.cast<String, dynamic>() ?? const {};
    final delivery = (j['delivery'] as Map?)?.cast<String, dynamic>() ?? const {};
    final secondsLeft = _in(j['seconds_left']) ?? 0;
    return Offer(
      id: j['offer_id'],
      // نعتمد على seconds_left لتفادي فرق الساعة بين الموبايل والسيرفر.
      expiresAt: DateTime.now().add(Duration(seconds: secondsLeft)),
      secondsLeft: secondsLeft,
      distanceToStoreKm: _dn(j['distance_to_store_km']),
      deliveryDistanceKm: _dn(j['delivery_distance_km']),
      earning: _d(j['earning']),
      collectAmount: _d(j['collect_amount']),
      storeName: store['name'] ?? '',
      storeAddress: store['address'],
      storePoint: _point(store['lat'], store['lng']),
      deliveryPoint: _point(delivery['lat'], delivery['lng']),
    );
  }
}

enum OrderStatus {
  pending('بانتظار المتجر'),
  accepted('المتجر قبل الطلب'),
  preparing('جاري التجهيز'),
  ready('جاهز للاستلام'),
  pickedUp('في الطريق للعميل'),
  delivered('تم التوصيل'),
  cancelled('ملغي');

  const OrderStatus(this.label);
  final String label;

  static OrderStatus parse(String? s) => switch (s) {
        'accepted' => accepted,
        'preparing' => preparing,
        'ready' => ready,
        'picked_up' => pickedUp,
        'delivered' => delivered,
        'cancelled' => cancelled,
        _ => pending,
      };

  bool get isActive => this != delivered && this != cancelled;
}

class OrderItem {
  OrderItem({required this.name, required this.quantity, required this.total, required this.optionsText, this.notes});

  final String name;
  final double quantity;
  final double total;
  final String optionsText;
  final String? notes;

  factory OrderItem.fromJson(Map<String, dynamic> j) => OrderItem(
        name: j['name'] ?? '',
        quantity: _d(j['quantity']),
        total: _d(j['total']),
        optionsText: _list(j['options']).map((o) => o['value'] ?? '').where((v) => '$v'.isNotEmpty).join('، '),
        notes: j['notes'],
      );
}

class OrderStore {
  OrderStore({required this.id, required this.name, this.phone, this.address, this.logo, this.point});

  final int id;
  final String name;
  final String? phone;
  final String? address;
  final String? logo;
  final LatLng? point;

  factory OrderStore.fromJson(Map<String, dynamic> j) => OrderStore(
        id: j['id'],
        name: j['name'] ?? '',
        phone: j['phone'],
        address: j['address'],
        logo: fixMediaUrl(j['logo']),
        point: _point(j['lat'], j['lng']),
      );
}

/// الطلب كما يراه السائق.
class Order {
  Order({
    required this.id,
    required this.number,
    required this.status,
    required this.statusLabel,
    this.store,
    this.customerName,
    this.customerPhone,
    this.deliveryAddress,
    this.deliveryPoint,
    this.distanceKm,
    required this.items,
    required this.total,
    required this.driverEarning,
    required this.collectAmount,
    required this.paymentMethod,
    this.notes,
    this.cancelReason,
    required this.timeline,
    this.createdAt,
  });

  final int id;
  final String number;
  final OrderStatus status;
  final String statusLabel;
  final OrderStore? store;
  final String? customerName;
  final String? customerPhone;
  final String? deliveryAddress;
  final LatLng? deliveryPoint;
  final double? distanceKm;
  final List<OrderItem> items;
  final double total;
  final double driverEarning;
  final double collectAmount;
  final String paymentMethod;
  final String? notes;
  final String? cancelReason;
  final Map<String, DateTime?> timeline;
  final DateTime? createdAt;

  DateTime? get arrivedAt => timeline['driver_arrived_at'];
  DateTime? get pickedUpAt => timeline['picked_up_at'];
  DateTime? get deliveredAt => timeline['delivered_at'];

  /// خطوة السائق الحالية: 0 = في الطريق للمتجر، 1 = في المتجر، 2 = في الطريق للعميل، 3 = انتهى.
  int get driverStep {
    if (!status.isActive) return 3;
    if (status == OrderStatus.pickedUp) return 2;
    if (arrivedAt != null) return 1;
    return 0;
  }

  factory Order.fromJson(Map<String, dynamic> j) {
    final delivery = (j['delivery'] as Map?)?.cast<String, dynamic>() ?? const {};
    final customer = (j['customer'] as Map?)?.cast<String, dynamic>() ?? const {};
    final timeline = (j['timeline'] as Map?)?.cast<String, dynamic>() ?? const {};

    return Order(
      id: j['id'],
      number: '${j['number'] ?? j['id']}',
      status: OrderStatus.parse(j['status']),
      statusLabel: j['status_label'] ?? '',
      store: j['store'] is Map ? OrderStore.fromJson((j['store'] as Map).cast<String, dynamic>()) : null,
      customerName: customer['name'],
      customerPhone: customer['phone'],
      deliveryAddress: delivery['address'],
      deliveryPoint: _point(delivery['lat'], delivery['lng']),
      distanceKm: _dn(delivery['distance_km']),
      items: _list(j['items']).map(OrderItem.fromJson).toList(),
      total: _d(j['total']),
      driverEarning: _d(j['driver_earning']),
      collectAmount: _d(j['collect_amount']),
      paymentMethod: j['payment_method'] ?? 'cash',
      notes: j['notes'],
      cancelReason: j['cancel_reason'],
      timeline: timeline.map((k, v) => MapEntry(k, _dt(v))),
      createdAt: _dt(j['created_at']),
    );
  }
}

class Period {
  Period({required this.earnings, required this.orders});
  final double earnings;
  final int orders;

  factory Period.fromJson(Object? j) {
    final m = (j as Map?) ?? const {};
    return Period(earnings: _d(m['earnings']), orders: _in(m['orders']) ?? 0);
  }
}

class Transaction {
  Transaction({required this.id, required this.typeLabel, required this.amount, this.description, this.orderId, this.createdAt});

  final int id;
  final String typeLabel;
  final double amount;
  final String? description;
  final int? orderId;
  final DateTime? createdAt;

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: j['id'],
        typeLabel: j['type_label'] ?? j['type'] ?? '',
        amount: _d(j['amount']),
        description: j['description'],
        orderId: _in(j['order_id']),
        createdAt: _dt(j['created_at']),
      );
}

class Earnings {
  Earnings({
    required this.today,
    required this.week,
    required this.month,
    required this.cashInHand,
    required this.cashLimit,
    required this.balance,
    required this.transactions,
  });

  final Period today;
  final Period week;
  final Period month;
  final double cashInHand;
  final double cashLimit;

  /// موجب = المنصة مدينة للسائق، سالب = عليه توريده.
  final double balance;
  final List<Transaction> transactions;

  factory Earnings.fromJson(Map<String, dynamic> j) => Earnings(
        today: Period.fromJson(j['today']),
        week: Period.fromJson(j['week']),
        month: Period.fromJson(j['month']),
        cashInHand: _d(j['cash_in_hand']),
        cashLimit: _d(j['cash_limit']),
        balance: _d(j['balance']),
        transactions: _list(j['transactions']).map(Transaction.fromJson).toList(),
      );
}

class TicketMessage {
  TicketMessage({required this.body, required this.isMine, required this.sender, this.createdAt});

  final String body;
  final bool isMine;
  final String sender;
  final DateTime? createdAt;

  factory TicketMessage.fromJson(Map<String, dynamic> j) =>
      TicketMessage(body: j['body'] ?? '', isMine: j['is_mine'] == true, sender: j['sender'] ?? '', createdAt: _dt(j['created_at']));
}

class Ticket {
  Ticket({required this.id, required this.subject, required this.status, required this.statusLabel, required this.messages, this.updatedAt});

  final int id;
  final String subject;
  final String status;
  final String statusLabel;
  final List<TicketMessage> messages;
  final DateTime? updatedAt;

  factory Ticket.fromJson(Map<String, dynamic> j) => Ticket(
        id: j['id'],
        subject: j['subject'] ?? '',
        status: j['status'] ?? '',
        statusLabel: j['status_label'] ?? '',
        messages: _list(j['messages']).map(TicketMessage.fromJson).toList(),
        updatedAt: _dt(j['updated_at']),
      );
}
