import 'package:flutter/material.dart';
import 'package:cookmate/pages/homescreen.dart' show Recipe, HomeScreen;
import 'package:cookmate/authentication/auth.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cookmate/pages/camerascreen.dart';
import 'package:cookmate/items_names/vegetables.dart' as veg;
import 'package:cookmate/items_names/meat.dart' as meat;
import 'package:cookmate/items_names/dairy.dart' as dairy;
import 'package:cookmate/items_names/spices.dart' as spices;
import 'package:cookmate/items_names/grains.dart' as grains;
import 'package:cookmate/config/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cookmate/pages/detailrecipe.dart';

@immutable
class SearchScreen extends StatefulWidget {
  final String? initialSearch;
  final List<Recipe>? recipes;

  const SearchScreen({Key? key, this.initialSearch, this.recipes})
    : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Recipe> _searchResults = [];
  List<Recipe> _partialResults = [];
  bool _isLoading = false;
  bool _isLoadingRecent = false;
  Timer? _debounce;
  List<String> _recentSearches = [];
  bool _showRecent = false;
  bool _showPartialMessage = false;
  String _partialMessage = '';

  // Update categories to be derived from actual recipe data
  List<String> _categories = [];

  // Add quick-add items organized by category
  final Map<String, List<String>> _quickAddItems = {
    'Vegetables': veg.Vegetables.items,
    'Meat': meat.Meat.items,
    'Dairy': dairy.Dairy.items,
    'Spices': spices.Spices.items,
    'Grains': grains.Grains.items,
  };

  // Define a constant for the number of items to show initially
  static const int _initialItemCount = 3;

  // Track expanded categories
  final Set<String> _expandedCategories = {};

  // Use a user-specific key for recent searches so each user has their own history
  String get _recentSearchesKey {
    final userId = Auth().userId ?? 'guest';
    return 'recent_searches_$userId';
  }

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoadSearches();
    _loadRecentSearches();
    _initializeCategories();
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchController.text = widget.initialSearch!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.initialSearch!);
      });
      _showRecent = false;
    } else {
      _showRecent = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    setState(() {
      _isLoadingRecent = true;
    });
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList(_recentSearchesKey) ?? [];
      _isLoadingRecent = false;
    });
  }

  Future<void> _addToRecentSearches(String query) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> searches = prefs.getStringList(_recentSearchesKey) ?? [];
    searches.remove(query);
    searches.insert(0, query);
    if (searches.length > 10) searches = searches.sublist(0, 10);
    await prefs.setStringList(_recentSearchesKey, searches);
    setState(() {
      _recentSearches = searches;
    });
  }

  Future<void> _performSearch(String query) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    setState(() {
      _isLoading = true;
      _showRecent = false;
      _showPartialMessage = false;
      _partialMessage = '';
    });

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;

      // Use all recipes for searching, not just the current user's
      final allRecipes = widget.recipes ?? HomeScreen.recipes;
      final lowerQuery = query.toLowerCase();
      final queryParts =
          lowerQuery
              .split(RegExp(r'[\,\s]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();

      // Exact match: recipe must contain ALL and ONLY the searched ingredients OR name matches exactly
      final exactResults =
          allRecipes.where((recipe) {
            final ingredients =
                (recipe.ingredients ?? [])
                    .map((i) => i.toLowerCase().trim())
                    .toList();
            final nameMatch =
                (recipe.title?.toLowerCase().trim() ?? '') == lowerQuery;
            return nameMatch ||
                (ingredients.length == queryParts.length &&
                    queryParts.every((part) => ingredients.contains(part)));
          }).toList();

      if (exactResults.isNotEmpty) {
        setState(() {
          _searchResults = exactResults;
          _partialResults = [];
          _showPartialMessage = false;
          _isLoading = false;
        });
      } else {
        // Partial match: recipe must contain ALL searched ingredients (but may have more) OR name contains query
        final partialResults =
            allRecipes.where((recipe) {
              final ingredients =
                  (recipe.ingredients ?? [])
                      .map((i) => i.toLowerCase().trim())
                      .toList();
              final nameContains = (recipe.title?.toLowerCase() ?? '').contains(
                lowerQuery,
              );
              return nameContains ||
                  queryParts.every(
                    (part) => ingredients.any(
                      (ingredient) => ingredient.contains(part),
                    ),
                  );
            }).toList();
        setState(() {
          _searchResults = partialResults;
          _partialResults = partialResults;
          _showPartialMessage = true;
          _partialMessage =
              "We don't have a recipe with exactly your ingredients, but here are some that use all your ingredients plus a few more, or match your search by name.";
          _isLoading = false;
        });
      }

      if (query.trim().isNotEmpty) {
        _addToRecentSearches(query.trim());
      }
    });
  }

  Future<void> _checkAuthAndLoadSearches() async {
    // You can leave this empty or add your authentication/search loading logic here.
  }

  Future<void> _clearRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentSearchesKey);
    setState(() {
      _recentSearches = [];
    });
  }

  void _initializeCategories() {
    final allRecipes = widget.recipes ?? HomeScreen.recipes;
    if (allRecipes == null) {
      print('No recipes available for category initialization!');
      setState(() {
        _categories = [];
      });
      return;
    }
    final Set<String> categorySet = {};

    // Extract categories from recipes
    for (var recipe in allRecipes) {
      if (recipe.category != null && recipe.category!.isNotEmpty) {
        categorySet.add(recipe.category!);
      }
    }

    setState(() {
      _categories = categorySet.toList()..sort();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: TextField(
          enableInteractiveSelection: true,
          autofocus: false,
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: 'Search recipes...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.black38),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
          ),
          style: const TextStyle(color: Colors.black),
          cursorColor: Colors.black,
          onTapOutside: (event) => FocusScope.of(context).unfocus(),
          onChanged: (value) {
            if (value.isEmpty) {
              setState(() {
                _showRecent = true;
              });
              _loadRecentSearches();
            } else {
              setState(() {
                _showRecent = false;
              });
              _performSearch(value);
            }
          },
          onTap: () {
            if (_searchController.text.isEmpty) {
              setState(() {
                _showRecent = true;
              });
              _loadRecentSearches();
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              if (_searchController.text.isNotEmpty) {
                _performSearch(_searchController.text);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_a_photo),
            tooltip: 'Add more items from camera',
            onPressed: () async {
              final newItems = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) =>
                          CameraPage(initialSearch: _searchController.text),
                ),
              );
              if (newItems != null &&
                  newItems is String &&
                  newItems.isNotEmpty) {
                final current = _searchController.text;
                final currentSet =
                    current
                        .split(',')
                        .map((e) => e.trim().toLowerCase())
                        .where((e) => e.isNotEmpty)
                        .toSet();
                final newSet =
                    newItems
                        .split(',')
                        .map((e) => e.trim().toLowerCase())
                        .where((e) => e.isNotEmpty)
                        .toSet();
                final allItems = [...currentSet, ...newSet];
                final combinedSearch = allItems.join(', ');
                _searchController.text = combinedSearch;
                _performSearch(combinedSearch);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Recipe categories section

          // Quick add items section
          Container(
            height: 200,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _quickAddItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, categoryIndex) {
                String category = _quickAddItems.keys.elementAt(categoryIndex);
                List<String> items = _quickAddItems[category]!;

                return Container(
                  width: 150,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          category,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, itemIndex) {
                            return ListTile(
                              dense: true,
                              title: Text(items[itemIndex]),
                              onTap: () {
                                final current = _searchController.text;
                                final currentSet =
                                    current
                                        .split(',')
                                        .map((e) => e.trim())
                                        .where((e) => e.isNotEmpty)
                                        .toSet();
                                currentSet.add(items[itemIndex]);
                                final combinedSearch = currentSet.join(', ');
                                _searchController.text = combinedSearch;
                                _performSearch(combinedSearch);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Existing search results section
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _showRecent
                    ? (_isLoadingRecent
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Recent Searches',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _clearRecentSearches,
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            ),
                            ..._recentSearches.map(
                              (search) => ListTile(
                                leading: const Icon(Icons.history),
                                title: Text(search),
                                onTap: () {
                                  _searchController.text = search;
                                  setState(() {
                                    _showRecent = false;
                                  });
                                  _performSearch(search);
                                },
                              ),
                            ),
                          ],
                        ))
                    : (_searchController.text.isNotEmpty &&
                        _searchResults.isEmpty)
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No recipes found',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                    : Column(
                      children: [
                        if (_showPartialMessage)
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              _partialMessage,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _uniqueRecipes(_searchResults).length,
                            padding: const EdgeInsets.all(8.0),
                            itemBuilder: (context, index) {
                              final recipe =
                                  _uniqueRecipes(_searchResults)[index];
                              return _RecipeImageCard(recipe: recipe);
                            },
                          ),
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }
}

List<Recipe> _uniqueRecipes(List<Recipe> recipes) {
  final seen = <String>{};
  final unique = <Recipe>[];
  for (var recipe in recipes) {
    final key = (recipe.title ?? '') + (recipe.imageUrl ?? '');
    if (!seen.contains(key)) {
      seen.add(key);
      unique.add(recipe);
    }
  }
  return unique;
}

class _RecipeImageCard extends StatelessWidget {
  final Recipe recipe;
  const _RecipeImageCard({Key? key, required this.recipe}) : super(key: key);

  Future<String?> _getImageUrl() async {
    if (recipe.imageUrl == null || recipe.imageUrl!.isEmpty) return null;
    String imageName = recipe.imageUrl!;
    // If imageName is a full URL, extract only the file name
    if (imageName.startsWith('http')) {
      Uri uri = Uri.parse(imageName);
      imageName =
          uri.pathSegments.isNotEmpty ? uri.pathSegments.last : imageName;
    }
    final firstUrl = ApiConfig.getImageUrl(imageName);
    final secondUrl = ApiConfig.getImageUrl('images/foodimages/$imageName');
    try {
      final response = await http.get(
        Uri.parse(firstUrl),
        headers: {'Range': 'bytes=0-0'},
      );
      if (response.statusCode == 200 || response.statusCode == 206) {
        return firstUrl;
      } else {
        final response2 = await http.get(
          Uri.parse(secondUrl),
          headers: {'Range': 'bytes=0-0'},
        );
        if (response2.statusCode == 200 || response2.statusCode == 206) {
          return secondUrl;
        }
      }
    } catch (e) {
      try {
        final response2 = await http.get(
          Uri.parse(secondUrl),
          headers: {'Range': 'bytes=0-0'},
        );
        if (response2.statusCode == 200 || response2.statusCode == 206) {
          return secondUrl;
        }
      } catch (e) {}
    }
    return imageName;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getImageUrl(),
      builder: (context, snapshot) {
        String? imageUrl = snapshot.data;
        // Improved card styling with tap to detail
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
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                        errorWidget:
                            (context, url, error) =>
                                const Icon(Icons.image_not_supported, size: 50),
                      ),
                    )
                  else
                    const Icon(Icons.image_not_supported, size: 50),
                  const SizedBox(height: 12),
                  Text(
                    recipe.title ?? 'No Title',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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
