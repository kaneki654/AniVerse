import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/aniverse_loader.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<dynamic> _results = [];
  bool _loading = false;
  bool _searched = false;

  /// Search id of the request in flight. A slow response for an earlier query
  /// must not overwrite results for a later one.
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Wait for a pause in typing rather than firing a request per keystroke.
    _debounce = Timer(const Duration(milliseconds: 450), () => _run(value));
  }

  Future<void> _run(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _loading = false;
      });
      return;
    }

    final id = ++_requestId;
    setState(() => _loading = true);
    final results = await ApiService.search(q);
    if (!mounted || id != _requestId) return;
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search anime...',
            hintStyle: const TextStyle(color: Colors.white38),
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white54),
                    onPressed: () {
                      _controller.clear();
                      _run('');
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (v) {
            setState(() {}); // keep the clear button in sync
            _onChanged(v);
          },
          onSubmitted: _run,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AniVerseLoadingScreen(label: 'SEARCHING');
    }
    if (!_searched) {
      return const Center(
        child: Text('Type to search', style: TextStyle(color: Colors.white38)),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text('No results', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, i) {
        final anime = _results[i] as Map<String, dynamic>;
        final titles = (anime['title'] ?? {}) as Map<String, dynamic>;
        final title = titles['english'] ?? titles['romaji'] ?? 'Unknown';
        final poster = ((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '';
        final episodes = anime['episodes'];
        final status = anime['status'];

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 50,
              height: 70,
              child: poster.toString().isEmpty
                  ? const ColoredBox(color: Colors.white10)
                  : CachedNetworkImage(
                      imageUrl: poster,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.white10),
                    ),
            ),
          ),
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            [
              if (episodes != null) '$episodes eps',
              if (status != null) status.toString().replaceAll('_', ' '),
            ].join(' • '),
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          onTap: () => Navigator.push(
            context,
            FadeScaleRoute(page: DetailScreen(id: anime['id'].toString()),
            ),
          ),
        );
      },
    );
  }
}
