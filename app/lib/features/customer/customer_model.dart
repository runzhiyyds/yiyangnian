class CustomerModel {
  final String name;
  final String? phone;
  final String? lunarBirthday;
  final DateTime? solarBirthday;
  final String? zodiac;
  final int? age;
  final String? address;
  final int? lifeNumber;
  final String? symptoms;
  final DateTime? createdAt;

  CustomerModel({
    required this.name,
    this.phone,
    this.lunarBirthday,
    this.solarBirthday,
    this.zodiac,
    this.age,
    this.address,
    this.lifeNumber,
    this.symptoms,
    this.createdAt,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    DateTime? solar;
    if (json['solar_birthday'] != null) {
      solar = DateTime.parse(json['solar_birthday'] as String);
    }
    DateTime? createdAt;
    if (json['created_at'] != null) {
      createdAt = DateTime.parse(json['created_at'] as String);
    }
    return CustomerModel(
      name: json['name'] as String,
      phone: json['phone'] as String?,
      lunarBirthday: json['lunar_birthday'] as String?,
      solarBirthday: solar,
      zodiac: json['zodiac'] as String?,
      age: json['age'] as int?,
      address: json['address'] as String?,
      lifeNumber: json['life_number'] as int?,
      symptoms: json['symptoms'] as String?,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'lunar_birthday': lunarBirthday,
      'solar_birthday': solarBirthday?.toIso8601String().split('T').first,
      'zodiac': zodiac,
      'age': age,
      'address': address,
      'life_number': lifeNumber,
      'symptoms': symptoms,
    };
  }

  CustomerModel copyWith({
    String? name,
    String? phone,
    String? lunarBirthday,
    DateTime? solarBirthday,
    String? zodiac,
    int? age,
    String? address,
    int? lifeNumber,
    String? symptoms,
  }) {
    return CustomerModel(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      lunarBirthday: lunarBirthday ?? this.lunarBirthday,
      solarBirthday: solarBirthday ?? this.solarBirthday,
      zodiac: zodiac ?? this.zodiac,
      age: age ?? this.age,
      address: address ?? this.address,
      lifeNumber: lifeNumber ?? this.lifeNumber,
      symptoms: symptoms ?? this.symptoms,
      createdAt: createdAt,
    );
  }
}
