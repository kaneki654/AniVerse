import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? homeData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await ApiService.getHomeData();
    setState(() {
      homeData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ANIVERSE', style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 24)),
        centerTitle: true,
      ),
      body: homeData == null
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE50914)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection('Trending Now', homeData!['trending']),
                const SizedBox(height: 24),
                _buildSection('Popular', homeData!['popular']),
                const SizedBox(height: 24),
                _buildSection('Latest Episodes', homeData!['latest']),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<dynamic>? animes) {
    if (animes == null || animes.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: animes.length,
            itemBuilder: (context, index) {
              return AnimeCard(
                anime: animes[index],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => DetailScreen(id: animes[index]['id'].toString())),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
