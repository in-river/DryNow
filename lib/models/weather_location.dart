class WeatherLocation {
  final String name;
  final double latitude;
  final double longitude;
  final String? administrativeArea;
  final String? country;

  const WeatherLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.administrativeArea,
    this.country,
  });

  static const kasukabe = WeatherLocation(
    name: '春日部市',
    latitude: 35.9795,
    longitude: 139.7523,
    administrativeArea: '埼玉県',
    country: '日本',
  );

  static WeatherLocation? fromOpenMeteoJson(Map<String, dynamic> json) {
    final name = json['name'];
    final latitude = _finiteNumber(json['latitude']);
    final longitude = _finiteNumber(json['longitude']);
    if (name is! String ||
        name.trim().isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    return WeatherLocation(
      name: name.trim(),
      latitude: latitude,
      longitude: longitude,
      administrativeArea: _optionalText(json['admin1']),
      country: _optionalText(json['country']),
    );
  }

  String get details {
    final parts = <String>[];
    for (final value in [administrativeArea, country]) {
      if (value != null && value != name && !parts.contains(value)) {
        parts.add(value);
      }
    }
    return parts.join('・');
  }

  static double? _finiteNumber(dynamic value) =>
      value is num && value.isFinite ? value.toDouble() : null;

  static String? _optionalText(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }
}
