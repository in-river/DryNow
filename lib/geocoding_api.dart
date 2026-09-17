import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models/weather_location.dart';

class GeocodingResponse {
  final List<WeatherLocation> locations;
  final DateTime fetchedAt;
  final String rawJson;

  GeocodingResponse({
    required List<WeatherLocation> locations,
    required this.fetchedAt,
    required this.rawJson,
  }) : locations = List.unmodifiable(locations);
}

class GeocodingApi {
  final http.Client _client;
  final Duration timeout;

  GeocodingApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  Future<GeocodingResponse> search(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return GeocodingResponse(
        locations: const [],
        fetchedAt: DateTime.now().toUtc(),
        rawJson: '{}',
      );
    }

    GeocodingResponse? lastResponse;
    for (final candidate in _searchCandidates(normalizedQuery)) {
      final response = await _searchOnce(candidate);
      if (response.locations.isNotEmpty) return response;
      lastResponse = response;
    }
    return lastResponse!;
  }

  Future<GeocodingResponse> _searchOnce(String query) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': query,
      'count': '10',
      'language': 'ja',
      'format': 'json',
    });
    late http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw Exception('地点検索がタイムアウトしました。');
    } on http.ClientException {
      throw Exception('地点検索サービスに接続できませんでした。');
    }
    final fetchedAt = DateTime.now().toUtc();
    if (response.statusCode != 200) {
      throw Exception('地点検索に失敗しました（HTTP ${response.statusCode}）。');
    }

    final rawJson = utf8.decode(response.bodyBytes);
    final payload = jsonDecode(rawJson);
    if (payload is! Map<String, dynamic> || payload['error'] == true) {
      throw const FormatException('地点検索データの形式が不正です。');
    }
    final results = payload['results'];
    if (results != null && results is! List) {
      throw const FormatException('地点検索結果の形式が不正です。');
    }
    final locations = <WeatherLocation>[];
    for (final result in results as List? ?? const []) {
      if (result is! Map) continue;
      final location = WeatherLocation.fromOpenMeteoJson(
        Map<String, dynamic>.from(result),
      );
      if (location != null) locations.add(location);
    }
    return GeocodingResponse(
      locations: locations,
      fetchedAt: fetchedAt,
      rawJson: rawJson,
    );
  }

  List<String> _searchCandidates(String query) {
    final hasJapanese = RegExp(r'[一-龠々ぁ-んァ-ヶ]').hasMatch(query);
    final hasKnownSuffix = RegExp(r'[都道府県市区町村駅]$').hasMatch(query);
    if (!hasJapanese || hasKnownSuffix) return [query];
    // Open-Meteoでは「東京」「熊谷」より「東京都」「熊谷市」の方が自治体を正しく検索できる。
    return [
      '$query市',
      '$query区',
      '$query都',
      '$query道',
      '$query府',
      '$query県',
      query,
    ];
  }

  void close() => _client.close();
}
