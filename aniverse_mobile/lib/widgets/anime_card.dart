import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AnimeCard extends StatelessWidget {
  final Map<String, dynamic> anime;
  final VoidCallback onTap;

  const AnimeCard({super.key, required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = anime['title'] != null ? (anime['title']['english'] ?? anime['title']['romaji']) : 'Unknown';
    final image = anime['coverImage'] != null ? anime['coverImage']['large'] : '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: image,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
