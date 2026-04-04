import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'watch_screen.dart';

class DetailScreen extends StatefulWidget {
  final String id;
  const DetailScreen({super.key, required this.id});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  Map<String, dynamic>? anime;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final data = await ApiService.getAnimeDetails(widget.id);
    setState(() {
      anime = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (anime == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFE50914))));
    }

    final title = anime!['title']['english'] ?? anime!['title']['romaji'];
    final epCount = anime!['episodes'] ?? 12;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CachedNetworkImage(
              imageUrl: anime!['coverImage']['large'],
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(anime!['description']?.replaceAll(RegExp(r'<[^>]*>' ), '') ?? '', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  const Text('Episodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (anime!['status'] == 'NOT_YET_RELEASED')
                    const Center(child: Text('This Anime Hasn\'t been released yet', style: TextStyle(color: Colors.red, fontSize: 16)))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: epCount,
                      itemBuilder: (context, index) {
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2A2A2A)),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => WatchScreen(animeId: widget.id, epNum: index + 1)));
                          },
                          child: Text('${index + 1}'),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
