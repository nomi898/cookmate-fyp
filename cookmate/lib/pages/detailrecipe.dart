import 'package:flutter/material.dart';
import 'package:cookmate/pages/homescreen.dart'; // Import your HomeScreen
import 'dart:io';
import 'package:cookmate/authentication/auth.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:cookmate/services/api_services.dart';
import 'package:cookmate/utils/events.dart'; // Changed path
import 'package:cached_network_image/cached_network_image.dart';

class RecipeDetailPage extends StatefulWidget {
  final Recipe recipe;
  final String? customImageUrl;

  const RecipeDetailPage({Key? key, required this.recipe, this.customImageUrl})
    : super(key: key);

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  bool isLiked = false;

  @override
  void initState() {
    super.initState();
    _checkIfLiked();
    // Add event bus listener
    eventBus.on<LikeUpdatedEvent>().listen((_) {
      _checkIfLiked();
    });
  }

  Future<void> _checkIfLiked() async {
    if (!Auth().isLoggedIn) return;
    try {
      final likedRecipes = await ApiService.getLikedRecipes(Auth().userId!);
      if (mounted) {
        setState(() {
          isLiked = likedRecipes.any((recipe) => recipe.id == widget.recipe.id);
        });
      }
    } catch (e) {
      print('Error checking like status: $e');
    }
  }

  Future<void> _toggleLike() async {
    if (!Auth().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to like recipes')),
      );
      return;
    }

    try {
      if (isLiked) {
        await ApiService.unlikeRecipe(widget.recipe.id);
      } else {
        await ApiService.likeRecipe(widget.recipe.id);
      }
      setState(() {
        isLiked = !isLiked;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to ${isLiked ? 'unlike' : 'like'} recipe'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new),
        ),
        title: Text(widget.recipe.title ?? 'Recipe Details'),
        actions: [
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? Colors.red : null,
            ),
            onPressed: _toggleLike,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background:
                  (widget.customImageUrl != null &&
                          widget.customImageUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                        imageUrl: widget.customImageUrl!,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                        errorWidget:
                            (context, url, error) => const Center(
                              child: Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                      )
                      : (widget.recipe.imageUrl != null
                          ? CachedNetworkImage(
                            imageUrl: ApiConfig.getImageUrl(
                              widget.recipe.imageUrl!,
                            ),
                            fit: BoxFit.cover,
                            placeholder:
                                (context, url) => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                            errorWidget:
                                (context, url, error) => const Center(
                                  child: Icon(
                                    Icons.error_outline,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                          )
                          : const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              color: Colors.white,
                              size: 40,
                            ),
                          )),
            ),
          ),
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    widget.recipe.title ?? 'No Title',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Ingredients",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  if (widget.recipe.ingredients != null)
                    for (var ingredient in widget.recipe.ingredients!)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text("• $ingredient"),
                      )
                  else
                    const Text("No ingredients listed"),
                  const SizedBox(height: 16),
                  const Text(
                    "Instructions",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  if (widget.recipe.instructions != null &&
                      widget.recipe.instructions!.isNotEmpty)
                    Text(widget.recipe.instructions!)
                  else
                    const Text("No instructions available"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up event bus subscription
    eventBus.on<LikeUpdatedEvent>().listen((_) {}).cancel();
    super.dispose();
  }

  String get baseUrl =>
      Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';
}
