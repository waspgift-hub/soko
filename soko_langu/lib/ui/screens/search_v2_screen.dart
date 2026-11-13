import 'package:flutter/material.dart';

import '../../services/search_service.dart';
import '../tokens.dart';
import '../widgets/ui_button.dart';

class SearchV2Screen extends StatefulWidget {
  const SearchV2Screen({super.key});

  @override
  State<SearchV2Screen> createState() => _SearchV2ScreenState();
}

class _SearchV2ScreenState extends State<SearchV2Screen> {
  final _ctrl = TextEditingController();
  final _service = SearchService();
  bool _loading = false;
  String? _error;
  List<SearchResult> _results = const [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _service.globalSearch(query: q, pageSize: 20);
      setState(() => _results = resp.results);
    } catch (e) {
      setState(() => _error = 'Imeshindikana kutafuta.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tafuta')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UiSpace.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Tafuta bidhaa...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: UiSpace.sm),
                UiPrimaryButton(label: 'Tafuta', onPressed: _search),
              ],
            ),
          ),
          Expanded(child: _buildResults(context)),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_results.isEmpty) return const Center(child: Text('Hakuna matokeo.'));
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _results[i];
        return ListTile(
          title: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(r.price == null ? '' : 'TSh ${r.price!.round()}'),
        );
      },
    );
  }
}
