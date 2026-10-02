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
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.discount = 0,
    required this.total,
    this.commissionAmount = 0,
    this.storeNet = 0,
    this.prepMinutes,
    this.driver,
    this.isLate = false,
    this.estimatedDeliveryAt,
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
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;

  /// للتاجر: عمولة المنصة وصافي المتجر.
  final double commissionAmount;
  final double storeNet;
  final int? prepMinutes;

  /// السائق المسند (يظهر للتاجر).
  final OrderDriver? driver;
  final bool isLate;
  final DateTime? estimatedDeliveryAt;
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
  DateTime? get cancelledAt => timeline['cancelled_at'];
  DateTime? get driverArrivedAt => timeline['driver_arrived_at'];

  int get itemsCount => items.fold(0, (sum, i) => sum + i.quantity.ceil());

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
      subtotal: _d(j['subtotal']),
      deliveryFee: _d(j['delivery_fee']),
      discount: _d(j['discount']),
      total: _d(j['total']),
      commissionAmount: _d(j['commission_amount']),
      storeNet: _d(j['store_net']),
      prepMinutes: _in(j['prep_minutes']),
      driver: j['driver'] is Map ? OrderDriver.fromJson((j['driver'] as Map).cast<String, dynamic>()) : null,
      isLate: j['is_late'] == true,
      estimatedDeliveryAt: _dt(j['estimated_delivery_at']),
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

class OrderDriver {
  OrderDriver({this.name, this.phone, this.vehicleLabel, this.plate});

  final String? name;
  final String? phone;
  final String? vehicleLabel;
  final String? plate;

  factory OrderDriver.fromJson(Map<String, dynamic> j) =>
      OrderDriver(name: j['name'], phone: j['phone'], vehicleLabel: j['vehicle_type_label'], plate: j['vehicle_plate']);
}

// ---------------- التاجر ----------------

/// متجر التاجر كما يرجع من GET /vendor/store.
class VendorStore {
  VendorStore({
    required this.id,
    required this.name,
    this.logo,
    this.phone,
    this.address,
    this.typeName,
    required this.isOpen,
    required this.isOpenNow,
    required this.approvalStatus,
    required this.approvalLabel,
    required this.avgPrepMinutes,
  });

  final int id;
  final String name;
  final String? logo;
  final String? phone;
  final String? address;
  final String? typeName;

  /// زر الفتح/الإغلاق اليدوي.
  final bool isOpen;

  /// مفتوح فعلًا الآن (الزر + مواعيد العمل).
  final bool isOpenNow;
  final String approvalStatus;
  final String approvalLabel;
  final int avgPrepMinutes;

  bool get isApproved => approvalStatus == 'approved';

  /// [j] هو رد GET /vendor/store كاملًا: { data, approval_status, is_open, ... }.
  factory VendorStore.fromResponse(Map<String, dynamic> j) {
    final d = (j['data'] as Map).cast<String, dynamic>();
    return VendorStore(
      id: d['id'],
      name: d['name'] ?? '',
      logo: fixMediaUrl(d['logo']),
      phone: d['phone'],
      address: d['address'],
      typeName: (d['store_type'] as Map?)?['name'],
      isOpen: j['is_open'] == true,
      isOpenNow: d['is_open_now'] == true,
      approvalStatus: j['approval_status'] ?? 'approved',
      approvalLabel: j['approval_status_label'] ?? '',
      avgPrepMinutes: _in(d['avg_prep_minutes']) ?? 20,
    );
  }
}

/// متجر في قائمة متاجر التاجر (لو عنده أكثر من متجر).
class StoreSummary {
  StoreSummary({required this.id, required this.name, this.logo});

  final int id;
  final String name;
  final String? logo;

  factory StoreSummary.fromJson(Map<String, dynamic> j) => StoreSummary(id: j['id'], name: j['name'] ?? '', logo: fixMediaUrl(j['logo']));
}

class Category {
  Category({required this.id, required this.name, this.isActive = true, this.sort = 0});

  final int id;
  final String name;
  final bool isActive;
  final int sort;

  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(id: j['id'], name: j['name'] ?? '', isActive: j['is_active'] != false, sort: _in(j['sort']) ?? 0);
}

enum ProductUnit {
  piece('قطعة'),
  kg('كيلو'),
  gram('جرام'),
  liter('لتر'),
  pack('عبوة'),
  box('علبة');

  const ProductUnit(this.label);
  final String label;

  static ProductUnit parse(String? s) => ProductUnit.values.firstWhere((u) => u.name == s, orElse: () => piece);
}

/// قيمة داخل مجموعة إضافات (قابلة للتعديل في شاشة المنتج).
class OptionValueData {
  OptionValueData({this.name = '', this.price = 0, this.isAvailable = true});

  String name;
  double price;
  bool isAvailable;

  factory OptionValueData.fromJson(Map<String, dynamic> j) =>
      OptionValueData(name: j['name'] ?? '', price: _d(j['price']), isAvailable: j['is_available'] != false);
}

/// مجموعة إضافات: اختيار واحد (حجم) أو متعدد (إضافات).
class ProductOptionData {
  ProductOptionData({this.name = '', this.isMultiple = false, this.isRequired = false, this.maxSelections, List<OptionValueData>? values})
      : values = values ?? [OptionValueData()];

  String name;
  bool isMultiple;
  bool isRequired;
  int? maxSelections;
  List<OptionValueData> values;

  factory ProductOptionData.fromJson(Map<String, dynamic> j) => ProductOptionData(
        name: j['name'] ?? '',
        isMultiple: j['type'] == 'multiple',
        isRequired: j['is_required'] == true,
        maxSelections: j['type'] == 'multiple' ? _in(j['max_selections']) : null,
        values: _list(j['values']).map(OptionValueData.fromJson).toList(),
      );
}

class Product {
  Product({
    required this.id,
    this.categoryId,
    required this.name,
    this.description,
    this.image,
    required this.price,
    this.comparePrice,
    this.unit = ProductUnit.piece,
    required this.isAvailable,
    this.isActive = true,
    this.options = const [],
  });

  final int id;
  final int? categoryId;
  final String name;
  final String? description;
  final String? image;
  final double price;
  final double? comparePrice;
  final ProductUnit unit;
  final bool isAvailable;

  /// غير النشط مخفي تمامًا عن العملاء (بخلاف "غير متوفر" المؤقت).
  final bool isActive;
  final List<Map<String, dynamic>> options;

  String get unitLabel => unit.label;

  List<ProductOptionData> get editableOptions => options.map(ProductOptionData.fromJson).toList();

  Product copyWith({required bool isAvailable}) => Product(
        id: id,
        categoryId: categoryId,
        name: name,
        description: description,
        image: image,
        price: price,
        comparePrice: comparePrice,
        unit: unit,
        isAvailable: isAvailable,
        isActive: isActive,
        options: options,
      );

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'],
        categoryId: _in(j['category_id']),
        name: j['name'] ?? '',
        description: j['description'],
        image: fixMediaUrl(j['image']),
        price: _d(j['price']),
        comparePrice: _dn(j['compare_price']),
        unit: ProductUnit.parse(j['unit']),
        isAvailable: j['is_available'] == true,
        isActive: j['is_active'] != false,
        options: _list(j['options']),
      );
}

/// مواعيد يوم واحد. day_of_week: 0 = الأحد ... 6 = السبت.
class StoreHour {
  StoreHour({required this.dayOfWeek, this.isClosed = false, this.opensAt = '09:00', this.closesAt = '23:00'});

  static const dayNames = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

  final int dayOfWeek;
  bool isClosed;
  String opensAt;
  String closesAt;

  String get dayName => dayNames[dayOfWeek];

  factory StoreHour.fromJson(Map<String, dynamic> j) => StoreHour(
        dayOfWeek: _in(j['day_of_week']) ?? 0,
        isClosed: j['is_closed'] == true,
        opensAt: j['opens_at'] ?? '09:00',
        closesAt: j['closes_at'] ?? '23:00',
      );

  Map<String, dynamic> toJson() => {
        'day_of_week': dayOfWeek,
        'is_closed': isClosed,
        'opens_at': isClosed ? null : opensAt,
        'closes_at': isClosed ? null : closesAt,
      };
}

// ---------------- التسويات ----------------

class PaymentMethodOption {
  PaymentMethodOption({required this.value, required this.label});

  final String value;
  final String label;

  factory PaymentMethodOption.fromJson(Map<String, dynamic> j) => PaymentMethodOption(value: j['value'] ?? '', label: j['label'] ?? '');
}

/// سائق وصّل طلبات كاش للمتجر — يمكن تسجيل استلام كاش منه.
class FinanceDriver {
  FinanceDriver({required this.id, required this.name, this.phone, required this.cashInHand, required this.suggestedAmount, required this.pendingAmount});

  final int id;
  final String name;
  final String? phone;
  final double cashInHand;

  /// قيمة أصناف طلباته الكاش بعد آخر تسوية مؤكدة (بحد أقصى ما معه).
  final double suggestedAmount;
  final double pendingAmount;

  double get available => (cashInHand - pendingAmount).clamp(0, double.infinity).toDouble();

  factory FinanceDriver.fromJson(Map<String, dynamic> j) => FinanceDriver(
        id: j['id'],
        name: j['name'] ?? '',
        phone: j['phone'],
        cashInHand: _d(j['cash_in_hand']),
        suggestedAmount: _d(j['suggested_amount']),
        pendingAmount: _d(j['pending_amount']),
      );
}

class FinanceSummary {
  FinanceSummary({
    required this.balance,
    required this.pendingPayout,
    required this.pendingPayment,
    required this.pendingCount,
    required this.methods,
    required this.drivers,
  });

  /// موجب = المنصة مدينة للمتجر، سالب = على المتجر للمنصة.
  final double balance;
  final double pendingPayout;
  final double pendingPayment;
  final int pendingCount;
  final List<PaymentMethodOption> methods;
  final List<FinanceDriver> drivers;

  double get payoutAvailable => (balance - pendingPayout).clamp(0, double.infinity).toDouble();
  double get paymentDue => (-balance - pendingPayment).clamp(0, double.infinity).toDouble();

  factory FinanceSummary.fromJson(Map<String, dynamic> j) => FinanceSummary(
        balance: _d(j['balance']),
        pendingPayout: _d(j['pending_payout']),
        pendingPayment: _d(j['pending_payment']),
        pendingCount: _in(j['pending_count']) ?? 0,
        methods: _list(j['methods']).map(PaymentMethodOption.fromJson).toList(),
        drivers: _list(j['drivers']).map(FinanceDriver.fromJson).toList(),
      );
}

enum SettlementKind {
  payoutRequest('payout_request', 'طلب صرف الرصيد'),
  paymentReport('payment_report', 'تحويل للمنصة'),
  driverCash('driver_cash', 'استلام كاش من سائق');

  const SettlementKind(this.key, this.label);
  final String key;
  final String label;

  static SettlementKind parse(String? s) => SettlementKind.values.firstWhere((k) => k.key == s, orElse: () => payoutRequest);
}

/// طلب تسوية (للتاجر) أو تسليم كاش بانتظار تأكيد السائق.
class SettlementRequest {
  SettlementRequest({
    required this.id,
    required this.kind,
    required this.kindLabel,
    required this.amount,
    this.methodLabel,
    this.reference,
    this.notes,
    this.receipt,
    required this.status,
    required this.statusLabel,
    this.rejectionReason,
    this.storeName,
    this.storePhone,
    this.driverName,
    this.driverPhone,
    this.createdAt,
  });

  final int id;
  final SettlementKind kind;
  final String kindLabel;
  final double amount;
  final String? methodLabel;
  final String? reference;
  final String? notes;
  final String? receipt;
  final String status;
  final String statusLabel;
  final String? rejectionReason;
  final String? storeName;
  final String? storePhone;
  final String? driverName;
  final String? driverPhone;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory SettlementRequest.fromJson(Map<String, dynamic> j) {
    final store = (j['store'] as Map?)?.cast<String, dynamic>() ?? const {};
    final driver = (j['driver'] as Map?)?.cast<String, dynamic>() ?? const {};
    return SettlementRequest(
      id: j['id'],
      kind: SettlementKind.parse(j['kind']),
      kindLabel: j['kind_label'] ?? '',
      amount: _d(j['amount']),
      methodLabel: j['method_label'],
      reference: j['reference'],
      notes: j['notes'],
      receipt: fixMediaUrl(j['receipt']),
      status: j['status'] ?? 'pending',
      statusLabel: j['status_label'] ?? '',
      rejectionReason: j['rejection_reason'],
      storeName: store['name'],
      storePhone: store['phone'],
      driverName: driver['name'],
      driverPhone: driver['phone'],
      createdAt: _dt(j['created_at']),
    );
  }
}


class TopProduct {
  TopProduct({required this.name, required this.quantity, required this.revenue});

  final String name;
  final double quantity;
  final double revenue;

  factory TopProduct.fromJson(Map<String, dynamic> j) =>
      TopProduct(name: j['name'] ?? '', quantity: _d(j['quantity']), revenue: _d(j['revenue']));
}

class SalesSummary {
  SalesSummary({
    required this.ordersCount,
    required this.deliveredCount,
    required this.cancelledCount,
    required this.sales,
    required this.commission,
    required this.net,
    required this.balance,
    required this.topProducts,
  });

  final int ordersCount;
  final int deliveredCount;
  final int cancelledCount;
  final double sales;
  final double commission;
  final double net;

  /// موجب = المنصة مدينة للمتجر، سالب = على المتجر توريده.
  final double balance;
  final List<TopProduct> topProducts;

  factory SalesSummary.fromJson(Map<String, dynamic> j) => SalesSummary(
        ordersCount: _in(j['orders_count']) ?? 0,
        deliveredCount: _in(j['delivered_count']) ?? 0,
        cancelledCount: _in(j['cancelled_count']) ?? 0,
        sales: _d(j['sales']),
        commission: _d(j['commission']),
        net: _d(j['net']),
        balance: _d(j['balance']),
        topProducts: _list(j['top_products']).map(TopProduct.fromJson).toList(),
      );
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
