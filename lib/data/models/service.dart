/// خدمت قابل ارائه — جدول services.
class Service {
  const Service({
    required this.id,
    required this.title,
    this.description = '',
    required this.price,
    required this.durationMinutes,
    this.bufferMinutes = 5,
    this.prepMinutes = 0,
    this.directCost,
    this.imageUrl,
    this.discountPrice,
    this.discountStartsAt,
    this.discountEndsAt,
    this.isActive = true,
    this.employeeIds = const [],
    this.category = 'عمومی',
    this.totalBookings = 0,
    this.maxPerDay,
    this.advanceDays = 30,
    this.requiresConfirmation = false,
    this.archivedAt,
    this.order = 0,
  });

  final String id;
  final String title;
  final String description;
  final num price;
  /// هزینه مستقیم هر بار ارائه خدمت؛ null یعنی هزینه ثبت نشده است.
  final num? directCost;
  final int durationMinutes;
  final int bufferMinutes;
  final int prepMinutes;
  /// آدرس تصویر خدمت؛ در حالت آفلاین می‌تواند مسیر asset باشد.
  final String? imageUrl;
  /// قیمت تخفیفی؛ فقط در بازه اعتبار اعمال می‌شود.
  final num? discountPrice;
  final DateTime? discountStartsAt;
  final DateTime? discountEndsAt;
  final bool isActive;
  final List<String> employeeIds;
  final String category;
  final int totalBookings;
  final int? maxPerDay;
  final int advanceDays;
  final bool requiresConfirmation;
  final DateTime? archivedAt;
  final int order;

  int get totalMinutes => prepMinutes + durationMinutes + bufferMinutes;

  bool isDiscountActiveAt(DateTime at) {
    if (discountPrice == null || discountPrice! < 0 || discountPrice! >= price) return false;
    final day = DateTime(at.year, at.month, at.day);
    if (discountStartsAt != null && day.isBefore(DateTime(discountStartsAt!.year, discountStartsAt!.month, discountStartsAt!.day))) return false;
    if (discountEndsAt != null && day.isAfter(DateTime(discountEndsAt!.year, discountEndsAt!.month, discountEndsAt!.day))) return false;
    return true;
  }

  num priceAt(DateTime at) => isDiscountActiveAt(at) ? discountPrice! : price;

  Service copyWith({
    String? id,
    String? title,
    String? description,
    num? price,
    num? directCost,
    bool clearDirectCost = false,
    int? durationMinutes,
    int? bufferMinutes,
    int? prepMinutes,
    String? imageUrl,
    bool clearImageUrl = false,
    num? discountPrice,
    bool clearDiscountPrice = false,
    DateTime? discountStartsAt,
    bool clearDiscountStartsAt = false,
    DateTime? discountEndsAt,
    bool clearDiscountEndsAt = false,
    bool? isActive,
    List<String>? employeeIds,
    String? category,
    int? totalBookings,
    int? maxPerDay,
    int? advanceDays,
    bool? requiresConfirmation,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    int? order,
  }) {
    return Service(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      directCost: clearDirectCost ? null : (directCost ?? this.directCost),
      durationMinutes: durationMinutes ?? this.durationMinutes,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      prepMinutes: prepMinutes ?? this.prepMinutes,
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      discountPrice: clearDiscountPrice ? null : (discountPrice ?? this.discountPrice),
      discountStartsAt: clearDiscountStartsAt ? null : (discountStartsAt ?? this.discountStartsAt),
      discountEndsAt: clearDiscountEndsAt ? null : (discountEndsAt ?? this.discountEndsAt),
      isActive: isActive ?? this.isActive,
      employeeIds: employeeIds ?? this.employeeIds,
      category: category ?? this.category,
      totalBookings: totalBookings ?? this.totalBookings,
      maxPerDay: maxPerDay ?? this.maxPerDay,
      advanceDays: advanceDays ?? this.advanceDays,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'price': price,
        'direct_cost': directCost,
        'duration_minutes': durationMinutes,
        'buffer_minutes': bufferMinutes,
        'prep_minutes': prepMinutes,
        'image_url': imageUrl,
        'discount_price': discountPrice,
        'discount_starts_at': discountStartsAt?.toUtc().toIso8601String(),
        'discount_ends_at': discountEndsAt?.toUtc().toIso8601String(),
        'is_active': isActive,
        'employee_ids': employeeIds,
        'category': category,
        'total_bookings': totalBookings,
        'max_per_day': maxPerDay,
        'advance_days': advanceDays,
        'requires_confirmation': requiresConfirmation,
        'archived_at': archivedAt?.toUtc().toIso8601String(),
        'order': order,
      };

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        price: json['price'] as num? ?? 0,
        directCost: json['direct_cost'] as num?,
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 30,
        bufferMinutes: (json['buffer_minutes'] as num?)?.toInt() ?? 5,
        prepMinutes: (json['prep_minutes'] as num?)?.toInt() ?? 0,
        imageUrl: json['image_url'] as String?,
        discountPrice: json['discount_price'] as num?,
        discountStartsAt: json['discount_starts_at'] == null ? null : DateTime.tryParse(json['discount_starts_at'] as String)?.toLocal(),
        discountEndsAt: json['discount_ends_at'] == null ? null : DateTime.tryParse(json['discount_ends_at'] as String)?.toLocal(),
        isActive: json['is_active'] as bool? ?? true,
        employeeIds: (json['employee_ids'] as List?)?.cast<String>() ?? const [],
        category: json['category'] as String? ?? 'عمومی',
        totalBookings: (json['total_bookings'] as num?)?.toInt() ?? 0,
        maxPerDay: (json['max_per_day'] as num?)?.toInt(),
        advanceDays: (json['advance_days'] as num?)?.toInt() ?? 30,
        requiresConfirmation: json['requires_confirmation'] as bool? ?? false,
        archivedAt: json['archived_at'] == null ? null : DateTime.tryParse(json['archived_at'] as String)?.toLocal(),
        order: (json['order'] as num?)?.toInt() ?? 0,
      );
}
