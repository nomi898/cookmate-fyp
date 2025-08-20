import 'package:flutter/material.dart';
import 'package:cookmate/services/api_services.dart';
import 'package:cookmate/authentication/auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cookmate/pages/homescreen.dart';
import 'package:cookmate/utils/events.dart';
import 'dart:async';
import 'package:cookmate/pages/detailrecipe.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;

class Likedrecipescreen extends StatefulWidget {
  const Likedrecipescreen({Key? key}) : super(key: key);

  @override
  State<Likedrecipescreen> createState() => _LikedrecipescreenState();
}

class _LikedrecipescreenState extends State<Likedrecipescreen> {
  List<Recipe> _likedRecipes = [];
  bool _isLoading = true;
  late StreamSubscription _likeSubscription;

  @override
  void initState() {
    super.initState();
    _loadLikedRecipes();
    _likeSubscription = eventBus.on<LikeUpdatedEvent>().listen((_) {
      if (mounted) {
        refreshLikedRecipes();
      }
    });
  }

  @override
  void dispose() {
    _likeSubscription.cancel();
    super.dispose();
  }

  void refreshLikedRecipes() {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });
    _loadLikedRecipes();
  }

  Future<void> _loadLikedRecipes() async {
    if (!Auth().isLoggedIn) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final recipes = await ApiService.getLikedRecipes(Auth().userId!);
      print(
        recipes
            .map(
              (r) => {
                'title': r.title,
                'likedAt': r.likedAt,
                'imageUrl': r.imageUrl,
              },
            )
            .toList(),
      );

      // Sort recipes by likedAt timestamp (oldest first, first-like first-come)
      recipes.sort(
        (a, b) => (b.likedAt ?? DateTime.now()).compareTo(
          a.likedAt ?? DateTime.now(),
        ),
      );

      if (mounted) {
        setState(() {
          _likedRecipes = recipes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _unlikeRecipe(String recipeId) async {
    try {
      await ApiService.unlikeRecipe(recipeId);
      await _loadLikedRecipes(); // Reload the list
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to unlike recipe: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _buildBody());
  }

  Widget _buildBody() {
    if (!Auth().isLoggedIn) {
      return _buildLoginPrompt();
    }

    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
          onRefresh: _loadLikedRecipes,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: _buildRecipeSections(),
          ),
        );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Please log in to see your liked recipes',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRecipeSections() {
    if (_likedRecipes.isEmpty) {
      return [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No liked recipes yet',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ];
    }

    final now = DateTime.now();
    final recentRecipes =
        _likedRecipes.where((recipe) {
          final likedAt = recipe.likedAt ?? now;
          return now.difference(likedAt).inDays < 7;
        }).toList();

    final olderRecipes =
        _likedRecipes.where((recipe) {
          final likedAt = recipe.likedAt ?? now;
          return now.difference(likedAt).inDays >= 7;
        }).toList();

    final sections = <Widget>[];

    if (recentRecipes.isNotEmpty) {
      sections.add(_buildSectionTitle('Recently Liked'));
      sections.addAll(
        recentRecipes.map((recipe) => _buildLikedRecipeItem(recipe)),
      );
      sections.add(const SizedBox(height: 16));
    }

    if (olderRecipes.isNotEmpty) {
      sections.add(_buildSectionTitle('Last Week'));
      sections.addAll(
        olderRecipes.map((recipe) => _buildLikedRecipeItem(recipe)),
      );
    }

    return sections;
  }

  Widget _buildLikedRecipeItem(Recipe recipe) {
    final likedAt = recipe.likedAt ?? DateTime.now();
    final timeAgo = timeago.format(likedAt);

    print('Recipe: \\${recipe.title}, likedAt: \\${recipe.likedAt}');

    return FutureBuilder<String>(
      future: _getRecipeImageUrl(recipe.imageUrl),
      builder: (context, snapshot) {
        String imageUrl = snapshot.data ?? '';
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (context) => RecipeDetailPage(
                      recipe: recipe,
                      customImageUrl: imageUrl,
                    ),
              ),
            );
          },
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Container(
                            height: 100,
                            width: 100,
                            color: Colors.grey[200],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            height: 100,
                            width: 100,
                            color: Colors.grey[200],
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 30,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe.title ?? 'Untitled Recipe',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.favorite,
                              color: Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Liked $timeAgo',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder:
                            (context) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(
                                    Icons.remove_circle_outline,
                                  ),
                                  title: const Text('Unlike Recipe'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _unlikeRecipe(recipe.id);
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.share),
                                  title: const Text('Share Recipe'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    // Implement share functionality
                                  },
                                ),
                              ],
                            ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String> _getRecipeImageUrl(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return '';
    if (imagePath.startsWith('http')) return imagePath;
    final baseUrl = ApiConfig.baseUrl;
    final url1 = '$baseUrl/uploads/$imagePath';
    final url2 = '$baseUrl/uploads/images/foodImages/$imagePath';
    // Try url1 first
    try {
      final response = await http.head(Uri.parse(url1));
      if (response.statusCode == 200) return url1;
    } catch (_) {}
    // Try url2 as fallback
    try {
      final response = await http.head(Uri.parse(url2));
      if (response.statusCode == 200) return url2;
    } catch (_) {}
    return '';
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
