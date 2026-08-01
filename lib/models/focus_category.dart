class FocusCategory {
  const FocusCategory({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    this.parentId,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final int colorValue;
  final String iconKey;
  final String? parentId;
  final bool isArchived;

  FocusCategory copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    String? parentId,
    bool clearParent = false,
    bool? isArchived,
  }) {
    return FocusCategory(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      parentId: clearParent ? null : parentId ?? this.parentId,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'iconKey': iconKey,
    'parentId': parentId,
    'isArchived': isArchived,
  };

  factory FocusCategory.fromJson(Map<String, Object?> json) {
    return FocusCategory(
      id: json['id']! as String,
      name: json['name']! as String,
      colorValue: json['colorValue']! as int,
      iconKey: (json['iconKey'] as String?) ?? 'work',
      parentId: json['parentId'] as String?,
      isArchived: (json['isArchived'] as bool?) ?? false,
    );
  }
}
