import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8001'; // For Android emulator. Use real IP for physical device.

  static Future<Map<String, dynamic>> getHomeData() async {
    try {
      final popularRes = await http.get(Uri.parse('$baseUrl/anime/popular?per_page=12'));
      final trendingRes = await http.get(Uri.parse('$baseUrl/anime/trending?per_page=12'));
      final latestRes = await http.get(Uri.parse('$baseUrl/anime/latest?per_page=12'));
      
      return {
        'popular': json.decode(popularRes.body),
        'trending': json.decode(trendingRes.body),
        'latest': json.decode(latestRes.body),
      };
    } catch (e) {
      print(e);
      return {};
    }
  }

  static Future<Map<String, dynamic>> getAnimeDetails(String id) async {
    const query = ''
    query ($id: Int) {
      Media (id: $id, type: ANIME) {
        id
        title { romaji english }
        description
        coverImage { large }
        episodes
        genres
        averageScore
        status
      }
    }
    '';
    final response = await http.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'query': query, 'variables': {'id': int.parse(id)}}),
    );
    return json.decode(response.body)['data']['Media'];
  }

  static Future<Map<String, dynamic>> getSources(String id, int epNum, String category) async {
    final response = await http.get(Uri.parse('$baseUrl/anime/resolve/$id/$epNum?category=$category'));
    return json.decode(response.body);
  }
}
