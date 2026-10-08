import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/app_settings.dart';
import '../widgets/pixel_extras.dart';
import '../pixel/pixel.dart';
import '../pixel/pixel_widgets.dart';
import '../pixel/sprites.dart';
import '../widgets/aniverse_logo.dart';
import '../widgets/poster_card.dart';
import '../widgets/aniverse_loader.dart';
import 'detail_screen.dart';

/// Search as you type, plus filters (genre, year, season, format, status,
/// minimum score, sort) -- the website's search page.
class SearchScreen extends StatefulWidget {
  /// Off when it is a tab: the keyboard should not jump up on app start.
  final bool autofocus;
  const SearchScreen({super.key, this.autofocus = true});

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

  // Filters; '' is "any".
  final Map<String, String> _filters = {};
  int _page = 1;
  bool _hasNext = false;
  bool _loadingMore = false;

  static final int _year = DateTime.now().year;
  static final Map<String, (String, List<(String, String)>)> _filterDefs = {
    'genres': ('Genre', [('', 'Any genre'), for (final g in ApiService.genres) (g, g)]),
    'year': ('Year', [('', 'Any year'), for (var y = _year + 1; y >= 1970; y--) ('$y', '$y')]),
    'season': ('Season', const [('', 'Any season'), ('WINTER', 'Winter'), ('SPRING', 'Spring'), ('SUMMER', 'Summer'), ('FALL', 'Fall')]),
    'format': ('Format', const [('', 'Any format'), ('TV', 'TV'), ('MOVIE', 'Movie'), ('OVA', 'OVA'), ('ONA', 'ONA'), ('SPECIAL', 'Special'), ('TV_SHORT', 'TV short')]),
    'status': ('Status', const [('', 'Any status'), ('RELEASING', 'Airing'), ('FINISHED', 'Finished'), ('NOT_YET_RELEASED', 'Upcoming')]),
    'min_score': ('Score', const [('', 'Any score'), ('60', '60+'), ('70', '70+'), ('80', '80+'), ('90', '90+')]),
    'sort': ('Sort', const [('', 'Best match'), ('POPULARITY_DESC', 'Popular'), ('SCORE_DESC', 'Top rated'), ('TRENDING_DESC', 'Trending'), ('START_DATE_DESC', 'Newest')]),
  };

  bool get _filtered => _filters.values.any((v) => v.isNotEmpty);

  Widget _filterBar() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        children: [
          for (final MapEntry(key: key, value: (label, options)) in _filterDefs.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChipButton(
                label: (_filters[key] ?? '').isEmpty
                    ? label
                    : options.firstWhere((o) => o.$1 == _filters[key], orElse: () => ('', label)).$2,
                onTap: () async {
                  final v = await pickOption(context, label, options, _filters[key] ?? '');
                  if (v == null) return;
                  setState(() => _filters[key] = v);
                  _run(_controller.text);
                },
              ),
            ),
          if (_filtered)
            ChoiceChipButton(label: 'Clear', onTap: () {
              setState(_filters.clear);
              _run(_controller.text);
            }),
        ],
      ),
    );
  }

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

  Future<void> _run(String query, {bool more = false}) async {
    final q = query.trim();
    if (_filtered) {
      final id = more ? _requestId : ++_requestId;
      final page = more ? _page + 1 : 1;
      setState(() => more ? _loadingMore = true : _loading = true);
      final r = await ApiService.filter({'q': q, ..._filters, 'page': '$page', 'per_page': '24'});
      if (!mounted || id != _requestId) return;
      setState(() {
        final media = (r['media'] as List? ?? const []);
        _results = more ? [..._results, ...media] : media;
        _page = page;
        _hasNext = r['hasNextPage'] == true;
        _loading = false;
        _loadingMore = false;
        _searched = true;
      });
      return;
    }
    _hasNext = false;
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
            autofocus: widget.autofocus,
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
            onSubmitted: (v) {
              AppSettings.addRecentSearch(v);
              _run(v);
            },
          ),
        ),
      ),
      body: Column(children: [_filterBar(), Expanded(child: _buildBody())]),
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
    if (!_searched) {
      final recent = AppSettings.recentSearches;
      if (recent.isEmpty) return _message(Sprites.search, 'TYPE OR PICK A FILTER');
      // Searches that led somewhere before, one tap to run again.
      return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
        Row(children: [
          Expanded(child: Text('RECENT SEARCHES', style: PxFont.label(8, color: Px.ash))),
          PixelButton(
            label: 'Clear',
            kind: PixelButtonKind.dark,
            fontSize: 7,
            onPressed: () async {
              await AppSettings.clearRecentSearches();
              if (mounted) setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final q in recent)
            ChoiceChipButton(
              label: q,
              onTap: () {
                _controller.text = q;
                _run(q);
                setState(() {});
              },
            ),
        ]),
      ]);
    }
    if (_results.isEmpty) return _message(Sprites.skull, 'NO RESULTS');

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _results.length + (_hasNext ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i >= _results.length) {
          return Center(
            child: PixelButton(
              label: 'Load more',
              kind: PixelButtonKind.dark,
              busy: _loadingMore,
              onPressed: () => _run(_controller.text, more: true),
            ),
          );
        }
        final anime = _results[i] as Map<String, dynamic>;
        final titles = (anime['title'] ?? {}) as Map<String, dynamic>;
        final title = (titles['english'] ?? titles['romaji'] ?? 'Unknown').toString();
        final poster = (((anime['coverImage'] ?? {}) as Map<String, dynamic>)['large'] ?? '').toString();
        final episodes = anime['episodes'];
        final status = anime['status'];

        return PressableScale(
          onTap: () {
            // Opening a result means the search found what it was for.
            AppSettings.addRecentSearch(_controller.text);
            Navigator.push(context, FadeScaleRoute(page: DetailScreen(id: anime['id'].toString())));
          },
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
