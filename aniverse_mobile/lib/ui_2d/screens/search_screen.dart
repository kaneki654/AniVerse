import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/poster_card.dart';
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
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: PxFont.text(17),
            decoration: InputDecoration(
              hintText: 'Search anime...',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: PixelSprite(Sprites.search, scale: 1.8, color: Px.ash),
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : PixelIconButton(
                      sprite: Sprites.close,
                      tooltip: 'Clear',
                      color: Px.ash,
                      scale: 1.8,
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
      ),
      body: _buildBody(),
    );
  }

  Widget _message(Sprite sprite, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelSprite(sprite, scale: 4, color: Px.ashDark),
            const SizedBox(height: 18),
            Text(text, style: PxFont.label(10, color: Px.ash)),
          ],
        ),
      );

  Widget _buildBody() {
    if (_loading) {
      return const AniVerseLoadingScreen(label: 'SEARCHING');
    }
    if (!_searched) return _message(Sprites.search, 'TYPE TO SEARCH');
    if (_results.isEmpty) return _message(Sprites.skull, 'NO RESULTS');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final anime = _results[i] as Map<String, dynamic>;
        final titles = (anime['title'] ?? {}) as Map<String, dynamic>;
        final title = (titles['english'] ?? titles['romaji'] ?? 'Unknown').toString();
        final poster = (((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '').toString();
        final episodes = anime['episodes'];
        final status = anime['status'];

        return PressableScale(
          onTap: () => Navigator.push(
            context,
            FadeScaleRoute(page: DetailScreen(id: anime['id'].toString())),
          ),
          child: SizedBox(
            height: 92,
            child: PixelBox(
              fill: Px.panel,
              child: Row(
                children: [
                  SizedBox(width: 60, child: PixelCover(url: poster, decodeWidth: 48)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: PxFont.text(15, height: 1.2)),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (episodes != null) '$episodes EPS',
                            if (status != null) status.toString().replaceAll('_', ' '),
                          ].join(' · '),
                          style: PxFont.label(7, color: Px.ash),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: PixelSprite(Sprites.chevron, scale: 1.6, color: Px.ashDark),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
