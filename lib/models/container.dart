class Container {
  final String name;
  final String image;
  final String status;
  final List<String> ports;

  Container({
    required this.name,
    required this.image,
    required this.status,
    this.ports = const [],
  });

  factory Container.fromJson(Map<String, dynamic> json) {
    return Container(
      name: json['name'] as String,
      image: json['image'] as String,
      status: json['status'] as String,
      ports: (json['ports'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'image': image,
      'status': status,
      'ports': ports,
    };
  }
}
