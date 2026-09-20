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
    return AlertDialog(
      scrollable: true,
      title: const Text('地点を変更'),
      content: SizedBox(
        key: const Key('location-search-content'),
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
            _buildSearchResult(),
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
      return const Padding(
        key: Key('location-search-loading'),
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 12),
            Text('地点を検索しています…'),
          ],
        ),
      );
    }
    if (_errorMessage != null) {
      return Padding(
        key: const Key('location-search-error'),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _errorMessage!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    if (_hasSearched && _locations.isEmpty) {
      return const Padding(
        key: Key('location-search-empty'),
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('該当する地点が見つかりませんでした。\n表記を変えて検索してください。'),
      );
    }
    if (!_hasSearched) {
      return Text(
        '市区町村名や地域名で検索できます。',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    final resultHeight = (_locations.length * 64.0).clamp(64.0, 280.0);
    return SizedBox(
      height: resultHeight,
      child: ListView.separated(
        key: const Key('location-search-results'),
        itemCount: _locations.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final location = _locations[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.location_on_outlined),
            title: Text(location.name),
            subtitle: location.details.isEmpty ? null : Text(location.details),
            onTap: () => Navigator.of(context).pop(location),
          );
        },
      ),
    );
  }

  String _readableError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(Exception|FormatException): '),
    '',
  );
}
