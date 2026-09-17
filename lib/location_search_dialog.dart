import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'geocoding_api.dart';
import 'models/weather_location.dart';

class LocationSearchDialog extends StatefulWidget {
  final GeocodingApi api;

  const LocationSearchDialog({super.key, required this.api});

  @override
  State<LocationSearchDialog> createState() => _LocationSearchDialogState();
}

class _LocationSearchDialogState extends State<LocationSearchDialog> {
  final _controller = TextEditingController();
  List<WeatherLocation> _locations = const [];
  String? _errorMessage;
  bool _isSearching = false;
  bool _hasSearched = false;
  int _requestSequence = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _locations = const [];
        _errorMessage = '検索する地名を入力してください。';
      });
      return;
    }

    final requestSequence = ++_requestSequence;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _locations = const [];
      _errorMessage = null;
    });
    try {
      final response = await widget.api.search(query);
      if (!mounted || requestSequence != _requestSequence) return;
      setState(() {
        _locations = response.locations;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted || requestSequence != _requestSequence) return;
      setState(() {
        _errorMessage = _readableError(error);
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultHeight = math.min(
      MediaQuery.sizeOf(context).height * 0.42,
      320.0,
    );
    return AlertDialog(
      title: const Text('地点を変更'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('location-search-field'),
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: '市区町村・地域名',
                hintText: '例：東京、熊谷',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  key: const Key('location-search-button'),
                  tooltip: '検索',
                  onPressed: _isSearching ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(height: resultHeight, child: _buildSearchResult()),
            const SizedBox(height: 8),
            Text(
              '現在地の利用は今後対応予定です。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }

  Widget _buildSearchResult() {
    if (_isSearching) {
      return const Center(
        key: Key('location-search-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('地点を検索しています…'),
          ],
        ),
      );
    }
    if (_errorMessage != null) {
      return Center(
        key: const Key('location-search-error'),
        child: Text(
          _errorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_hasSearched && _locations.isEmpty) {
      return const Center(
        key: Key('location-search-empty'),
        child: Text(
          '該当する地点が見つかりませんでした。\n表記を変えて検索してください。',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!_hasSearched) {
      return const Center(child: Text('地名を入力して検索してください。'));
    }
    return ListView.separated(
      key: const Key('location-search-results'),
      itemCount: _locations.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final location = _locations[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: Text(location.name),
          subtitle: location.details.isEmpty ? null : Text(location.details),
          onTap: () => Navigator.of(context).pop(location),
        );
      },
    );
  }

  String _readableError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Exception|FormatException): '),
    '',
  );
}
