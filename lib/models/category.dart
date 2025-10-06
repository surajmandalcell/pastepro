class Category {
  final int id;
  final String name;
  final int color;

  Category({required this.id, required this.name, required this.color});

  factory Category.fromMap(Map<String, dynamic> map) =>
      Category(id: map['id'] as int, name: map['name'] as String, color: map['color'] as int);
}

