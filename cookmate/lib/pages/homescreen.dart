// home_screen.dart
import 'package:cookmate/pages/searchscreen.dart';
import 'package:cookmate/pages/signin.dart';
import 'package:cookmate/pages/uploadrecipescreen.dart';
import 'package:cookmate/pages/likedrecipescreen.dart';
import 'package:cookmate/pages/profilescreen.dart';
import 'package:flutter/material.dart';
import 'package:cookmate/widgets/foodcard.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:cookmate/pages/camerascreen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:cookmate/authentication/auth.dart';
import 'package:cookmate/config/api_config.dart';
import 'dart:math';
import 'package:cookmate/services/recommendation_service.dart';
import 'package:cookmate/pages/detailrecipe.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  static List<Recipe> recipes = [];
  final int initialIndex;

  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  late final ValueNotifier<int> _selectedIndex;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _searchBarHeight = ValueNotifier<double>(0);
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final List<Recipe> _recipes = [];
  late List<Recipe> _recommendedRecipes = [];
  late List<Recipe> _remainingRecipes = [];
  bool _showRecommendations = true;
  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _hasMoreRecipes = true;
  String? _currentUserId;
  bool _isDisposed = false;

  String get baseUrl => ApiConfig.baseUrl;
  // Platform.isAndroid ? 'http://10.0.2.2:3000' : 'http://localhost:3000';

  @override
  void initState() {
    super.initState();
    _selectedIndex = ValueNotifier<int>(widget.initialIndex);
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _initializeAndLoadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _isDisposed = true;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app comes back to foreground
      _initializeAndLoadData();
    }
  }

  Future<void> _initializeAndLoadData() async {
    if (_isDisposed) return;

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _recipes.clear();
          _recommendedRecipes.clear();
          _remainingRecipes.clear();
        });
      }

      // Load recipes first without waiting for recommendations
      await _loadRecipes();

      // Initialize recommendation service and load recommendations in the background
      if (mounted && Auth().isLoggedIn) {
        _initializeRecommendations();
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // New method to handle recommendation initialization separately
  Future<void> _initializeRecommendations() async {
    try {
      final userId = Auth().userId;
      if (userId != null && Auth().isLoggedIn && mounted) {
        // Initialize recommendation service
        await RecommendationService.initialize(userId);

        // Load liked recipes and update preferences
        final response = await http
            .get(
              Uri.parse('${Auth().baseUrl}/api/users/$userId/liked-recipes'),
              headers: {
                ...Auth().authHeaders,
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final List<dynamic> likedRecipes = json.decode(response.body);
          final Set<String> ingredients = {};

          for (var recipeJson in likedRecipes) {
            try {
              final recipe = Recipe.fromJson(recipeJson);
              if (recipe.ingredients != null) {
                ingredients.addAll(recipe.ingredients!);
              }
            } catch (e) {
              // Handle error silently
            }
          }

          if (ingredients.isNotEmpty) {
            await RecommendationService.updateFavoriteIngredients(
              ingredients.toList(),
            );
          }
        }

        // Load recommendations after initial data is loaded
        if (mounted && _recipes.isNotEmpty) {
          await _loadRecommendations();
        }
      }
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isDisposed) return;

    final currentUserId = Auth().userId;
    if (_currentUserId != currentUserId && mounted) {
      // print('\n🔄 User changed from $_currentUserId to $currentUserId');
      _currentUserId = currentUserId;
      _initializeAndLoadData();
    }
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection ==
        ScrollDirection.reverse) {
      // Scrolling down - hide search bar
      _searchBarHeight.value = 80.0;
    } else if (_scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      // Scrolling up - show search bar
      _searchBarHeight.value = 0.0;
    }

    // Load more recipes when reaching the bottom
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 500 &&
        !_isLoadingMore &&
        _hasMoreRecipes) {
      _loadMoreRecipes();
    }
  }

  Future<void> _loadMoreRecipes() async {
    if (_isLoadingMore || !mounted || !_hasMoreRecipes) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await http
          .get(
            Uri.parse('${Auth().baseUrl}/api/recipes?page=${_currentPage + 1}'),
            headers: {
              ...Auth().authHeaders,
              'Content-Type': 'application/json',
            },
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(
                'Connection timeout while loading more recipes.',
              );
            },
          );

      // print('Load more response status: ${response.statusCode}');
      // print('Load more response body: ${response.body}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> recipesJson;

        if (data is Map<String, dynamic>) {
          recipesJson = data['recipes'] is List ? data['recipes'] : [];
        } else if (data is List) {
          recipesJson = data;
        } else {
          throw Exception('Unexpected response format');
        }

        final List<Recipe> newRecipes = [];
        for (var recipeJson in recipesJson) {
          try {
            final recipe = Recipe.fromJson(recipeJson);
            if (recipe.id.isNotEmpty) {
              newRecipes.add(recipe);
            }
          } catch (e) {
            // print('Error parsing individual recipe while loading more: $e');
          }
        }

        if (!mounted) return;

        setState(() {
          _remainingRecipes.addAll(newRecipes);
          _currentPage++;
          _hasMoreRecipes = recipesJson.length >= _pageSize;
          _isLoadingMore = false;
        });

        // print('Loaded ${newRecipes.length} more recipes');
      } else {
        setState(() {
          _hasMoreRecipes = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      // print('Error loading more recipes: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is TimeoutException
                  ? 'Connection timeout while loading more recipes.'
                  : 'Error loading more recipes.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _loadRecipes() async {
    if (!mounted) return;

    try {
      // print('\n📱 Loading recipes for physical device');
      // print('Using API URL: ${Auth().baseUrl}');
      // print('Current API configuration: ${ApiConfig.baseUrl}');
      // print('Auth headers: ${Auth().authHeaders}');

      setState(() {
        _isLoading = true;
        _currentPage = 1;
        _recipes.clear();
        _recommendedRecipes.clear();
        _remainingRecipes.clear();
      });

      // Load all recipes without user filtering
      final url = '${ApiConfig.baseUrl}/api/recipes';
      // print('Fetching recipes from: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              ...Auth().authHeaders,
            },
          )
          .timeout(
            const Duration(seconds: 30), // Increased timeout to 30 seconds
            onTimeout: () {
              // print('⚠️ Request timed out after 30 seconds');
              throw TimeoutException(
                'Connection timeout. Please check your internet connection.',
              );
            },
          );

      // print('Recipe loading response status: ${response.statusCode}');
      // print('Response headers: ${response.headers}');
      // print('Response body length: ${response.body.length}');

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        List<dynamic> recipesJson;

        // Handle different response formats
        if (data is Map<String, dynamic>) {
          recipesJson = data['recipes'] is List ? data['recipes'] : [];
        } else if (data is List) {
          recipesJson = data;
        } else {
          throw Exception('Unexpected response format');
        }

        // print('📥 Received ${recipesJson.length} recipes from server');

        // Safely parse recipes
        final List<Recipe> newRecipes = [];
        for (var recipeJson in recipesJson) {
          try {
            final recipe = Recipe.fromJson(recipeJson);
            if (recipe.id.isNotEmpty) {
              newRecipes.add(recipe);
            }
          } catch (e) {
            // print('❌ Error parsing individual recipe: $e');
          }
        }

        if (!mounted) return;

        // Shuffle the recipes before displaying them
        final random = Random();
        newRecipes.shuffle(random);

        // Get recommendations if user is logged in
        List<Recipe> recommendedRecipes = [];
        if (Auth().isLoggedIn) {
          try {
            final userId = Auth().userId;
            if (userId != null && userId.isNotEmpty) {
              // print('🔍 Getting recommendations for user: $userId');
              recommendedRecipes =
                  await RecommendationService.getRecommendedRecipes(
                    newRecipes,
                    userId, // Pass userId directly as a string
                  );
              // print('✅ Loaded ${recommendedRecipes.length} recommendations');
            } else {
              // print('⚠️ No valid user ID found for recommendations');
            }
          } catch (e) {
            // print('❌ Error getting recommendations: $e');
            // print('Stack trace: ${StackTrace.current}');
          }
        }

        if (!mounted) return;

        // Remove filtering logic for debugging
        // Instead of filtering, just return all recipes as-is
        Future<List<Recipe>> filterRecipesWithValidData(
          List<Recipe> recipes,
        ) async {
          return recipes;
        }

        final filteredRecipes = await filterRecipesWithValidData(newRecipes);
        setState(() {
          _recipes.addAll(filteredRecipes);

          if (recommendedRecipes.isNotEmpty) {
            _recommendedRecipes = recommendedRecipes;
            _remainingRecipes =
                filteredRecipes
                    .where((r) => !recommendedRecipes.contains(r))
                    .toList();
            _showRecommendations = true; // Ensure recommendations are shown
          } else {
            _remainingRecipes = filteredRecipes;
            _showRecommendations =
                false; // Hide recommendations section if none available
          }

          _hasMoreRecipes = recipesJson.length >= _pageSize;
          _isLoading = false;
        });

        // print('✅ Successfully loaded ${newRecipes.length} recipes');
        HomeScreen.recipes = _recipes;
      } else {
        // print('❌ Failed to load recipes: ${response.statusCode}');
        throw Exception('Failed to load recipes');
      }
    } catch (e) {
      // print('❌ Error loading recipes: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is TimeoutException
                  ? 'Connection timeout. Please check your internet connection.'
                  : 'Error loading recipes. Please try again.',
            ),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _loadRecipes(),
              textColor: Colors.white,
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadRecommendations() async {
    if (!mounted || _isDisposed || _recipes.isEmpty) return;

    try {
      // print('\n📱 Loading recommendations for HomeScreen');
      // print('👤 User: ${Auth().userId}');
      // print('Total recipes available: ${_recipes.length}');

      // First, get liked recipes to ensure we don't recommend them again
      final userId = Auth().userId;
      if (userId != null) {
        // print('🔍 Loading liked recipes to exclude from recommendations');
        final response = await http
            .get(
              Uri.parse('${Auth().baseUrl}/api/users/$userId/liked-recipes'),
              headers: {
                ...Auth().authHeaders,
                'Content-Type': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 15)); // Increased timeout

        if (response.statusCode == 200) {
          final List<dynamic> likedRecipes = json.decode(response.body);
          // print('✅ Found ${likedRecipes.length} liked recipes to exclude');

          // Extract liked recipe IDs
          final Set<String> likedRecipeIds = {};
          for (var recipeJson in likedRecipes) {
            try {
              final recipe = Recipe.fromJson(recipeJson);
              if (recipe.id.isNotEmpty) {
                likedRecipeIds.add(recipe.id);
              }
            } catch (e) {
              // print('❌ Error parsing liked recipe: $e');
            }
          }

          // Remove liked recipes from available recipes
          final availableRecipes =
              _recipes.where((r) => !likedRecipeIds.contains(r.id)).toList();
          // print(
          //   '📚 Found ${availableRecipes.length} recipes not already liked by user',
          // );

          if (availableRecipes.isEmpty) {
            // print('⚠️ No new recipes available for recommendations');
            setState(() {
              _recommendedRecipes = [];
              _remainingRecipes = List.from(_recipes);
            });
            return;
          }
        } else {
          // print('❌ Failed to load liked recipes: ${response.statusCode}');
        }
      }

      // print('🔄 Requesting recommendations from service');
      final recommendations = await RecommendationService.getRecommendedRecipes(
        _recipes,
        Auth().userId ?? '', // Pass userId as string with empty string fallback
      ).timeout(
        const Duration(seconds: 20), // Increased timeout
        onTimeout: () {
          // print(
          //   '⚠️ Recommendation timeout, falling back to content-based recommendations',
          // );
          return [];
        },
      );

      if (!mounted || _isDisposed) return;

      setState(() {
        if (recommendations.isNotEmpty) {
          // print(
          //   '✅ Received ${recommendations.length} personalized recommendations',
          // );

          // Deduplicate recommendations based on recipe ID
          final uniqueRecommendations = <Recipe>[];
          final seenIds = <String>{};
          for (var recipe in recommendations) {
            if (!seenIds.contains(recipe.id)) {
              uniqueRecommendations.add(recipe);
              seenIds.add(recipe.id);
            }
          }

          // print(
          //   '✅ After deduplication: ${uniqueRecommendations.length} unique recommendations',
          // );
          _recommendedRecipes = uniqueRecommendations;

          // Remove recommended recipes from remaining recipes to avoid duplicates
          final recommendedIds = uniqueRecommendations.map((r) => r.id).toSet();
          _remainingRecipes =
              _recipes.where((r) => !recommendedIds.contains(r.id)).toList();

          // print(
          //   '📚 Remaining recipes after recommendations: ${_remainingRecipes.length}',
          // );

          // Log some details about the recommended recipes
          // print('\n📊 Top recommended recipes:');
          // for (var i = 0; i < min(3, uniqueRecommendations.length); i++) {
          //   final recipe = uniqueRecommendations[i];
          //   print('${i + 1}. ${recipe.title}');
          //   print(
          //     '   - Ingredients: ${recipe.ingredients?.take(5).join(", ")}${(recipe.ingredients?.length ?? 0) > 5 ? "..." : ""}',
          //   );
          // }
        } else {
          // If no recommendations, show some random recipes instead
          // print(
          //   '⚠️ No personalized recommendations available, showing random recipes',
          // );
          final random = Random();
          final randomRecipes = List<Recipe>.from(_recipes);
          randomRecipes.shuffle(random);

          // Deduplicate random recommendations
          final uniqueRandomRecipes = <Recipe>[];
          final seenIds = <String>{};
          for (var recipe in randomRecipes) {
            if (!seenIds.contains(recipe.id) &&
                uniqueRandomRecipes.length < 10) {
              uniqueRandomRecipes.add(recipe);
              seenIds.add(recipe.id);
            }
          }

          _recommendedRecipes = uniqueRandomRecipes;

          // Remove recommended recipes from remaining recipes to avoid duplicates
          final recommendedIds = _recommendedRecipes.map((r) => r.id).toSet();
          _remainingRecipes =
              _recipes.where((r) => !recommendedIds.contains(r.id)).toList();

          // print(
          //   '📚 Remaining recipes after random selection: ${_remainingRecipes.length}',
          // );
        }
      });

      // print('✅ Loaded ${_recommendedRecipes.length} recommendations');
      // print('✅ Remaining recipes: ${_remainingRecipes.length}');
    } catch (e) {
      // print('❌ Error loading recommendations: $e');
      if (!mounted || _isDisposed) return;

      setState(() {
        _recommendedRecipes = [];
        _remainingRecipes = List.from(_recipes);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _selectedIndex,
      builder: (context, currentIndex, child) {
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: _getAppBarTitle(currentIndex),
            centerTitle: true,
            leading:
                currentIndex == 4
                    ? IconButton(
                      icon: const Icon(Icons.logout, color: Colors.red),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder:
                              (context) => AlertDialog(
                                title: const Text('Logout'),
                                content: const Text(
                                  'Are you sure you want to log out?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(
                                        context,
                                      ); // Close the dialog
                                    },
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => SignIn(),
                                        ),
                                      );
                                    },
                                    child: const Text('Logout'),
                                  ),
                                ],
                              ),
                        );
                      },
                    )
                    : null,
          ),
          body: _getBody(currentIndex),
          bottomNavigationBar: CurvedNavigationBar(
            backgroundColor: Colors.white,
            height: 75,
            color: Colors.green,
            items: const <Widget>[
              Icon(Icons.home, size: 30, color: Colors.white),
              Icon(Icons.file_upload, size: 30, color: Colors.white),
              Icon(Icons.camera_alt),
              Icon(Icons.favorite, size: 30, color: Colors.white),
              Icon(Icons.person, size: 30, color: Colors.white),
            ],
            index: currentIndex,
            onTap: (index) async {
              if (index == 1) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const UploadRecipeScreen(),
                  ),
                ).then((_) {
                  _selectedIndex.value = 0;
                });
              } else if (index == 2) {
                final detectedItems = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CameraPage()),
                );
                if (detectedItems != null &&
                    detectedItems is String &&
                    detectedItems.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              SearchScreen(initialSearch: detectedItems),
                    ),
                  );
                }
              } else {
                _selectedIndex.value = index;
              }
            },
          ),
        );
      },
    );
  }

  /// Dynamically update AppBar title
  Widget _getAppBarTitle(int currentIndex) {
    switch (currentIndex) {
      case 1:
        return const Text(
          'Upload',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 23),
        );
      case 3:
        return const Text(
          'Liked Recipes',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 23),
        );
      case 4:
        return const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 23),
        );
      default:
        return const Text(
          'Home',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 23),
        );
    }
  }

  Widget _getBody(int currentIndex) {
    switch (currentIndex) {
      case 0:
        return Stack(
          children: [
            Column(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: _searchBarHeight,
                  builder: (context, height, child) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 80 - height,
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => const SearchScreen(
                                        initialSearch: null,
                                      ),
                                ),
                              );
                            },
                            child: AbsorbPointer(
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: 'Search',
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child:
                      _recipes.isEmpty && _isLoading
                          ? _buildLoadingSkeleton()
                          : buildRecipeList(),
                ),
              ],
            ),
            if (_isLoading && _recipes.isEmpty)
              Container(
                color: Colors.black.withOpacity(0.1),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        );
      case 1:
        return const UploadRecipeScreen();
      case 2:
        return const CameraPage();
      case 3:
        return const Likedrecipescreen();
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildLoadingSkeleton() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _ShimmerBox(height: 24, width: 200),
        ),
        SizedBox(
          height: 245,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 5,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _ShimmerContainer(width: 190, height: 245),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: _ShimmerBox(height: 24, width: 150),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _ShimmerContainer(width: double.infinity, height: 280),
            );
          },
        ),
      ],
    );
  }

  Widget buildRecipeList() {
    return RefreshIndicator(
      onRefresh: _loadRecipes,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        itemCount:
            (!_showRecommendations || _recommendedRecipes.isEmpty)
                ? _remainingRecipes.length +
                    1 // +1 for "All Recipes" header
                : _remainingRecipes.length +
                    3, // +3 for both headers and recommendations
        itemBuilder: (context, index) {
          if (!_showRecommendations || _recommendedRecipes.isEmpty) {
            if (index == 0) {
              return _buildSectionHeader(
                'All Recipes',
                showToggle: _recommendedRecipes.isNotEmpty,
              );
            }
            return _buildRecipeCard(_remainingRecipes[index - 1]);
          }

          // Show recommendations section
          if (index == 0) {
            return _buildRecommendationHeader();
          }

          if (index == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // _buildRecommendationInfo(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 270,

                  child:
                      _recommendedRecipes.isEmpty
                          ? const Center(
                            child: Text('No recommendations available'),
                          )
                          : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _recommendedRecipes.length,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                            ),
                            itemBuilder: (context, recIndex) {
                              final uniqueRecipes =
                                  _recommendedRecipes.toSet().toList();
                              if (recIndex >= uniqueRecipes.length) return null;
                              final recipe = uniqueRecipes[recIndex];
                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: SizedBox(
                                  width: 190,
                                  child: _buildRecipeCard(
                                    recipe,
                                    isHorizontal: true,
                                  ),
                                ),
                              );
                            },
                          ),
                ),
              ],
            );
          }

          if (index == 2) {
            return _buildSectionHeader('All Recipes', showToggle: false);
          }

          final remainingIndex = index - 3;
          if (remainingIndex < _remainingRecipes.length) {
            return _buildRecipeCard(_remainingRecipes[remainingIndex]);
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, {bool showToggle = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          if (showToggle)
            IconButton(
              icon: Icon(
                _showRecommendations ? Icons.visibility : Icons.visibility_off,
                color: Colors.grey[600],
              ),
              onPressed: () {
                setState(() {
                  _showRecommendations = !_showRecommendations;
                  if (!_showRecommendations) {
                    _remainingRecipes = [..._recipes];
                  } else {
                    final recommendedIds =
                        _recommendedRecipes.map((r) => r.id).toSet();
                    _remainingRecipes =
                        _recipes
                            .where((r) => !recommendedIds.contains(r.id))
                            .toList();
                  }
                });
              },
              tooltip:
                  _showRecommendations
                      ? 'Hide recommendations'
                      : 'Show recommendations',
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendationHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Recommended for You',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: _showRecommendationInfo,
                tooltip: 'How recommendations work',
              ),
              IconButton(
                icon: Icon(
                  _showRecommendations
                      ? Icons.visibility
                      : Icons.visibility_off,
                  color: Colors.grey[600],
                ),
                onPressed: () {
                  setState(() {
                    _showRecommendations = !_showRecommendations;
                    if (!_showRecommendations) {
                      _remainingRecipes = [..._recipes];
                    } else {
                      final recommendedIds =
                          _recommendedRecipes.map((r) => r.id).toSet();
                      _remainingRecipes =
                          _recipes
                              .where((r) => !recommendedIds.contains(r.id))
                              .toList();
                    }
                  });
                },
                tooltip:
                    _showRecommendations
                        ? 'Hide recommendations'
                        : 'Show recommendations',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationInfo() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.amber[700], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'How We Pick These Recipes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRecommendationFactor(
              Icons.favorite,
              'Based on ${_recommendedRecipes.length} recipes you\'ve liked',
              Colors.red,
            ),
            _buildRecommendationFactor(
              Icons.restaurant,
              'Matching your favorite ingredients',
              Colors.orange,
            ),
            _buildRecommendationFactor(
              Icons.history,
              'Your cooking history',
              Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationFactor(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  void _showRecommendationInfo() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.amber[700]),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'How Recommendations Work',
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRecommendationDetail(
                    'Recipe Similarity',
                    'We analyze recipes you\'ve liked to find similar ones you might enjoy.',
                    Icons.favorite,
                    Colors.red,
                  ),
                  const SizedBox(height: 16),
                  _buildRecommendationDetail(
                    'Ingredient Matching',
                    'Recipes that use ingredients you frequently cook with or have liked.',
                    Icons.restaurant,
                    Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  _buildRecommendationDetail(
                    'Cooking History',
                    'We learn from the recipes you view and interact with.',
                    Icons.history,
                    Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  _buildRecommendationDetail(
                    'Fresh Discoveries',
                    'New recipes you haven\'t tried yet that match your taste.',
                    Icons.explore,
                    Colors.green,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
    );
  }

  Widget _buildRecommendationDetail(
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecipeCard(Recipe recipe, {bool isHorizontal = false}) {
    final imageUrl =
        recipe.imageUrl != null
            ? ApiConfig.getImageUrl(recipe.imageUrl!)
            : null;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      child: GestureDetector(
        onTap: () async {
          RecommendationService.recordInteraction(recipe).catchError((e) {
            // Handle error silently
          });
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RecipeDetailPage(recipe: recipe),
              ),
            );
          }
        },
        child: FoodCard(recipe: recipe, imageUrl: imageUrl),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double height;
  final double width;

  const _ShimmerBox({required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _ShimmerContainer extends StatelessWidget {
  final double width;
  final double height;

  const _ShimmerContainer({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

class Recipe {
  final String id;
  final String? title;
  final List<String>? ingredients;
  final DateTime? likedAt;
  final String? instructions;
  final String? category;
  final String? imageUrl;
  final String? userId;
  final DateTime? createdAt;
  String? _cachedFullImageUrl;
  bool _isLoadingImage = false;

  Recipe({
    required this.id,
    this.title,
    this.category,
    this.ingredients,
    this.instructions,
    this.imageUrl,
    this.userId,
    this.createdAt,
    this.likedAt,
  });

  // This will be used by widgets that need to display the image
  Future<String> getFullImageUrl() async {
    if (_cachedFullImageUrl != null) return _cachedFullImageUrl!;
    if (_isLoadingImage) return ''; // Prevent multiple simultaneous loads
    if (imageUrl == null || imageUrl!.isEmpty) return '';

    _isLoadingImage = true;
    try {
      // Use ApiConfig to handle the image URL consistently
      _cachedFullImageUrl = await ApiConfig.getImageUrl(imageUrl!);
      _isLoadingImage = false;
      return _cachedFullImageUrl ?? '';
    } catch (e) {
      _isLoadingImage = false;
      return '';
    }
  }

  // This is kept for backward compatibility but now uses the cached URL
  String get fullImageUrl => _cachedFullImageUrl ?? imageUrl ?? '';

  factory Recipe.fromJson(Map<String, dynamic> json) {
    try {
      // Handle different ID formats
      String recipeId = '';
      final rawId = json['_id'] ?? json['id'];
      if (rawId != null) {
        recipeId = rawId.toString();
      }

      // Handle ingredients
      List<String> ingredients = [];
      final rawIngredients = json['Cleaned_Ingredients'] ?? json['ingredients'];
      if (rawIngredients != null) {
        if (rawIngredients is List) {
          ingredients = rawIngredients.map((item) => item.toString()).toList();
        } else if (rawIngredients is String) {
          ingredients = rawIngredients.split(',').map((e) => e.trim()).toList();
        }
      }

      // Handle dates
      DateTime? createdAt;
      if (json['createdAt'] != null) {
        try {
          createdAt = DateTime.parse(json['createdAt'].toString());
        } catch (e) {
          // print('Error parsing createdAt: $e');
        }
      }

      DateTime? likedAt;
      if (json['likedAt'] != null) {
        try {
          likedAt = DateTime.parse(json['likedAt'].toString());
        } catch (e) {
          // print('Error parsing likedAt: $e');
        }
      }

      return Recipe(
        id: recipeId,
        title: (json['title'] ?? json['Title'])?.toString(),
        ingredients: ingredients,
        instructions:
            json['Instructions']?.toString() ??
            json['instructions']?.toString(),
        category: json['category'] as String?,
        imageUrl:
            (json['imageUrl'] ?? json['image'] ?? json['Image_Name'])
                ?.toString(),
        userId: json['userId']?.toString(),
        createdAt: createdAt,
        likedAt: likedAt,
      );
    } catch (e) {
      // print('Error parsing recipe JSON: $e');
      // print('Problematic JSON: $json');
      // Return a minimal valid recipe rather than throwing
      return Recipe(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Error Loading Recipe',
      );
    }
  }
}
