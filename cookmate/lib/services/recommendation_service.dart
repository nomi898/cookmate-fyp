import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cookmate/pages/homescreen.dart';
import 'package:cookmate/authentication/auth.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class RecommendationService {
  static String? _userId;
  static const String _lastLoginKey = 'last_login_timestamp';
  static const String _favoriteIngredientsKey = 'favorite_ingredients';
  static bool _usePythonServer = true;
  static bool _isInitialized = false;

  static String get baseUrl {
    return ApiConfig.mlUrl.isNotEmpty
        ? '${ApiConfig.mlUrl}/api'
        : '${ApiConfig.baseUrl}/api';
  }

  // Test connection to Python backend
  static Future<bool> testConnection() async {
    try {
      print('🔍 Testing recommendation server at: $baseUrl');
      print('Python server URL: ${ApiConfig.mlUrl}');
      print('Node server URL: ${ApiConfig.baseUrl}');

      // Try Python server first
      if (ApiConfig.mlUrl.isNotEmpty) {
        try {
          print('Attempting to connect to Python server...');
          final pythonResponse = await http
              .get(
                Uri.parse('${ApiConfig.mlUrl}/api/recipes'),
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 10)); // Increased timeout

          print(
            '📡 Python server response status: ${pythonResponse.statusCode}',
          );

          if (pythonResponse.statusCode == 200) {
            _usePythonServer = true;
            print('✅ Successfully connected to Python server');
            return true;
          }
        } catch (e) {
          print('❌ Python server connection failed: $e');
        }
      }

      // Fall back to Node.js server
      try {
        print('Attempting to connect to Node.js server...');
        final nodeResponse = await http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/api/recipes'),
              headers: {'Content-Type': 'application/json'},
            )
            .timeout(const Duration(seconds: 10)); // Increased timeout

        print('📡 Node.js server response status: ${nodeResponse.statusCode}');

        if (nodeResponse.statusCode == 200) {
          _usePythonServer = false;
          print('✅ Successfully connected to Node.js server');
          return true;
        }
      } catch (e) {
        print('❌ Node.js server connection failed: $e');
      }

      // If both servers fail, default to Node.js server
      print('⚠️ Both servers failed, defaulting to Node.js server');
      _usePythonServer = false;
      return true;
    } catch (e) {
      print('❌ Recommendation server connection failed: $e');
      // Default to Node.js server
      _usePythonServer = false;
      return true;
    }
  }

  // Initialize the service with user ID
  static Future<void> initialize(String userId) async {
    if (_isInitialized && _userId == userId) {
      print('🔄 RecommendationService already initialized for user: $userId');
      return;
    }

    print('\n🚀 Initializing recommendation service');
    print('👤 User ID: $userId');

    // Clear previous user's data if switching users
    if (_userId != null && _userId != userId) {
      print('🔄 Switching users, clearing previous data');
      await _clearUserData();
    }

    _userId = userId;

    try {
      await _updateLoginHistory();
      final isConnected = await testConnection();

      if (!isConnected) {
        print('⚠️ Warning: Recommendation service unavailable');
      } else {
        print('✅ Recommendation service connected successfully');
      }

      // Load initial preferences
      await _loadInitialPreferences();

      _isInitialized = true;
      print('✅ Recommendation service initialized for user: $userId');
    } catch (e) {
      print('❌ Error during initialization: $e');
      _isInitialized = false;
    }
  }

  // Clear user data when switching users
  static Future<void> _clearUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_userId != null) {
        await prefs.remove('${_userId}_$_lastLoginKey');
        await prefs.remove('${_userId}_$_favoriteIngredientsKey');
      }
      _isInitialized = false;
      print('✅ Previous user data cleared');
    } catch (e) {
      print('❌ Error clearing user data: $e');
    }
  }

  // Load initial user preferences
  static Future<void> _loadInitialPreferences() async {
    try {
      print('\n📝 Loading initial preferences');

      // Load liked recipes first
      final likedRecipes = await _getLikedRecipes();
      print('✅ Found ${likedRecipes.length} liked recipes');

      if (likedRecipes.isNotEmpty) {
        // Extract ingredients from liked recipes
        final ingredients = _extractIngredientsFromRecipes(likedRecipes);
        print(
          '🥗 Extracted ${ingredients.length} ingredients from liked recipes',
        );

        if (ingredients.isNotEmpty) {
          // Update favorite ingredients with ingredients from liked recipes
          await _updateFavoriteIngredients(ingredients);
          print('✅ Updated favorite ingredients from liked recipes');

          // Also store liked recipe IDs for future reference
          final likedRecipeIds =
              likedRecipes.map((r) => r['_id'] ?? r['id']).toList();
          print('📋 Stored ${likedRecipeIds.length} liked recipe IDs');
        } else {
          print('⚠️ No ingredients found in liked recipes');
        }
      } else {
        print('ℹ️ No liked recipes found for user');
      }

      // Load search history
      final searchHistory = await getUserSearchHistory();
      print('🔍 Loaded ${searchHistory.length} recent searches');

      final currentIngredients = await _getFavoriteIngredients();
      print('🥗 Loaded ${currentIngredients.length} favorite ingredients');
    } catch (e) {
      print('❌ Error loading initial preferences: $e');
    }
  }

  // Get liked recipes
  static Future<List<Map<String, dynamic>>> _getLikedRecipes() async {
    try {
      print('Loading liked recipes for user: $_userId');

      final response = await http.get(
        Uri.parse('${Auth().baseUrl}/api/users/$_userId/liked-recipes'),
        headers: {...Auth().authHeaders, 'Content-Type': 'application/json'},
      );

      print('Get liked recipes response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> recipes = json.decode(response.body);
        print('✅ Found ${recipes.length} liked recipes');
        return List<Map<String, dynamic>>.from(recipes);
      }
      print('❌ Failed to load liked recipes: ${response.statusCode}');
      return [];
    } catch (e) {
      print('❌ Error loading liked recipes: $e');
      return [];
    }
  }

  // Extract ingredients from recipes
  static List<String> _extractIngredientsFromRecipes(
    List<Map<String, dynamic>> recipes,
  ) {
    final Set<String> ingredients = {};
    for (var recipe in recipes) {
      try {
        final recipeObj = Recipe.fromJson(recipe);
        if (recipeObj.ingredients != null) {
          // Clean and normalize each ingredient
          for (var ingredient in recipeObj.ingredients!) {
            final cleaned = _cleanIngredient(ingredient);
            if (cleaned.isNotEmpty) {
              ingredients.add(cleaned);
            }
          }
        }
      } catch (e) {
        print('❌ Error extracting ingredients: $e');
      }
    }
    return ingredients.toList();
  }

  // Clean and normalize ingredient text
  static String _cleanIngredient(String ingredient) {
    try {
      // Convert to lowercase and trim
      var cleaned = ingredient.toLowerCase().trim();

      // Remove text in quotes
      cleaned = cleaned.replaceAll(RegExp(r'"[^"]*"'), '');

      // Remove measurements and quantities first
      cleaned = cleaned.replaceAll(
        RegExp(r'\d+(/\d+)?(\s*-\s*\d+(/\d+)?)?'),
        '',
      ); // Fractions and ranges
      cleaned = cleaned.replaceAll(RegExp(r'\d+\.?\d*'), ''); // Decimals
      cleaned = cleaned.replaceAll(
        RegExp(
          r'(cup|cups|tablespoon|tablespoons|teaspoon|teaspoons|ounce|ounces|pound|pounds|gram|grams|ml|g|kg|oz|lb|tbsp|tsp|bottle|can|package|stick|pinch|dash|handful|bunch|sprig|head|clove|piece|slice|container|jar)\s*(of)?',
        ),
        '',
      );

      // Remove common prep instructions and states
      cleaned = cleaned.replaceAll(
        RegExp(
          r'(chopped|minced|diced|sliced|grated|crushed|ground|peeled|seeded|cored|julienned|sifted|melted|softened|room temperature|chilled|fresh|dried|cooked|uncooked|prepared|ripe|thawed|frozen|warm|hot|cold|cooled|divided|plus more|to taste|approximately|about|around|roughly|finely|coarsely|thinly|thick|large|medium|small|mini|extra|very|well|just|good|quality|premium|fine|best)',
        ),
        '',
      );

      // Remove additional descriptors and states
      cleaned = cleaned.replaceAll(
        RegExp(
          r'(organic|natural|pure|raw|whole|refined|unrefined|unsweetened|sweetened|unsalted|salted|roasted|toasted|blanched|active|dry|fresh|ripe|young|aged|mature|baby|wild|cultivated|homemade|store-bought|prepared|ready-to-use|instant|quick|slow|low-sodium|reduced-fat|full-fat|non-fat|fat-free|light|heavy|mixed|assorted|various|any|good|best|premium|gourmet|specialty|basic|simple|regular|standard|optional|necessary|preferred|desired|favorite|choice|selected)',
        ),
        '',
      );

      // Remove parenthetical text
      cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

      // Remove specific cooking instructions
      cleaned = cleaned.replaceAll(
        RegExp(
          r'(at room temperature|for garnish|for serving|for decoration|to serve|to garnish|to taste|or more to taste|or to taste|plus more if needed|plus more as needed|if needed|as needed|if desired|if available|or more|or less|to your taste|according to taste|optional)',
        ),
        '',
      );

      // Remove punctuation and extra spaces
      cleaned = cleaned.replaceAll(
        RegExp(
          r'[,.*\-_/\\""'
          '`´]',
        ),
        ' ',
      );
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

      // Remove common joining words
      cleaned = cleaned.replaceAll(
        RegExp(
          r'\b(and|or|with|without|plus|for|the|a|an|some|few|in|on|at|by|to|into|onto|up|down|over|under|through|after|before|during|until|unless|if|then|else|when|where|while|because|since|although|though|even|just|only|also|too|very|quite|rather|somewhat|about|around|like|such|as|from|of)\b',
        ),
        ' ',
      );

      // Final cleanup of spaces
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

      return cleaned;
    } catch (e) {
      print('❌ Error cleaning ingredient: $e');
      return ingredient.toLowerCase().trim();
    }
  }

  // Update login history
  static Future<void> _updateLoginHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      await prefs.setString('${_userId}_$_lastLoginKey', now);
      print('📅 Updated last login time: $now');
    } catch (e) {
      print('❌ Error updating login history: $e');
    }
  }

  // Score recipes by matching ingredients
  static Map<String, dynamic>? _scoreRecipe(
    Recipe recipe,
    List<String> favoriteIngredients,
    List<Recipe> likedRecipeObjects,
  ) {
    try {
      final ingredients = recipe.ingredients ?? [];
      if (ingredients.isEmpty) return null;

      // Clean and normalize recipe ingredients
      final cleanedIngredients =
          ingredients
              .map(_cleanIngredient)
              .where(
                (i) => i.isNotEmpty && i.length > 1,
              ) // Filter out single characters
              .toList();
      if (cleanedIngredients.isEmpty) return null;

      // Clean favorite ingredients if not already cleaned
      final cleanedFavorites =
          favoriteIngredients
              .map(_cleanIngredient)
              .where((i) => i.isNotEmpty && i.length > 1)
              .toList();
      if (cleanedFavorites.isEmpty) return null;

      // Calculate ingredient match score
      final matchingIngredients =
          cleanedIngredients
              .where(
                (ingredient) => cleanedFavorites.any(
                  (fav) => ingredient.contains(fav) || fav.contains(ingredient),
                ),
              )
              .toList();

      // Calculate Jaccard similarity with more weight on exact matches
      double similarity = 0.0;
      if (matchingIngredients.isNotEmpty) {
        int exactMatches = 0;
        int partialMatches = 0;

        for (var ingredient in matchingIngredients) {
          if (cleanedFavorites.contains(ingredient)) {
            exactMatches++;
          } else {
            partialMatches++;
          }
        }

        similarity =
            (exactMatches * 1.0 + partialMatches * 0.5) /
            (cleanedIngredients.length +
                cleanedFavorites.length -
                exactMatches -
                partialMatches);
      }

      // Calculate ingredient overlap with liked recipes
      double likedRecipeOverlap = 0.0;
      if (likedRecipeObjects.isNotEmpty) {
        double totalOverlap = 0.0;
        for (var likedRecipe in likedRecipeObjects) {
          if (likedRecipe.ingredients != null) {
            final likedIngredients =
                likedRecipe.ingredients!
                    .map(_cleanIngredient)
                    .where((i) => i.isNotEmpty && i.length > 1)
                    .toList();

            int exactMatches = 0;
            int partialMatches = 0;

            for (var ingredient in cleanedIngredients) {
              if (likedIngredients.contains(ingredient)) {
                exactMatches++;
              } else if (likedIngredients.any(
                (liked) =>
                    ingredient.contains(liked) || liked.contains(ingredient),
              )) {
                partialMatches++;
              }
            }

            totalOverlap +=
                (exactMatches * 1.0 + partialMatches * 0.5) /
                max(cleanedIngredients.length, likedIngredients.length);
          }
        }
        likedRecipeOverlap = totalOverlap / likedRecipeObjects.length;
      }

      // Normalize scores to 0-1 range
      final normalizedSimilarity = similarity.clamp(0.0, 1.0);
      final normalizedOverlap = likedRecipeOverlap.clamp(0.0, 1.0);

      // Combine scores with weights
      final combinedScore =
          (normalizedSimilarity * 0.3) + (normalizedOverlap * 0.7);

      return {
        'recipe': recipe,
        'score': combinedScore,
        'matchCount': matchingIngredients.length,
        'matches': cleanedIngredients, // Show cleaned ingredients in logs
        'overlap': normalizedOverlap,
      };
    } catch (e) {
      print('❌ Error scoring recipe: $e');
      return null;
    }
  }

  // Get content-based recommendations using favorite ingredients
  static Future<List<Recipe>> _getContentBasedRecommendations(
    List<Recipe> allRecipes,
    List<String> favoriteIngredients,
  ) async {
    try {
      print('\n🧮 Calculating content-based recommendations');
      print('- Using ${favoriteIngredients.length} favorite ingredients');

      // First, try to get liked recipes to prioritize them
      final likedRecipes = await _getLikedRecipes();
      final List<Recipe> likedRecipeObjects = [];
      final Set<String> likedRecipeIds = {};

      if (likedRecipes.isNotEmpty) {
        print(
          '✅ Found ${likedRecipes.length} liked recipes to use for recommendations',
        );

        // Convert liked recipes to Recipe objects and collect their IDs
        for (var recipeJson in likedRecipes) {
          try {
            final recipe = Recipe.fromJson(recipeJson);
            if (recipe.id.isNotEmpty) {
              likedRecipeObjects.add(recipe);
              likedRecipeIds.add(recipe.id);
            }
          } catch (e) {
            print('❌ Error parsing liked recipe: $e');
          }
        }

        print(
          '✅ Converted ${likedRecipeObjects.length} liked recipes to objects',
        );
      }

      // Filter out recipes that the user has already liked
      final availableRecipes =
          allRecipes
              .where((recipe) => !likedRecipeIds.contains(recipe.id))
              .toList();
      print(
        '📚 Found ${availableRecipes.length} recipes not already liked by user',
      );

      if (availableRecipes.isEmpty) {
        print('⚠️ No new recipes available for recommendations');
        return [];
      }

      // Score all available recipes
      final scoredRecipes =
          availableRecipes
              .map(
                (recipe) => _scoreRecipe(
                  recipe,
                  favoriteIngredients,
                  likedRecipeObjects,
                ),
              )
              .where((item) => item != null)
              .toList();

      // Sort by combined score
      scoredRecipes.sort(
        (a, b) => (b!['score'] as double).compareTo(a!['score'] as double),
      );

      // Take top 20 recommendations
      final recommendations =
          scoredRecipes
              .take(20)
              .map((scored) => scored!['recipe'] as Recipe)
              .toList();

      // Log recommendation details
      print('\n📊 Top recommended recipes:');
      for (var i = 0; i < min(3, recommendations.length); i++) {
        final recipe = recommendations[i];
        final scored = scoredRecipes[i];
        print('${i + 1}. ${recipe.title}');
        print(
          '   - Combined Score: ${(scored?['score'] as double).toStringAsFixed(2)}',
        );
        print(
          '   - Matching Ingredients: ${(scored?['matches'] as List).join(", ")}',
        );
        print(
          '   - Liked Recipe Overlap: ${(scored?['overlap'] as double).toStringAsFixed(2)}',
        );
      }

      print(
        '\n✅ Generated ${recommendations.length} unique personalized recommendations',
      );
      return recommendations;
    } catch (e) {
      print('❌ Error in content-based recommendations: $e');
      return [];
    }
  }

  // Get recommended recipes with enhanced personalization
  static Future<List<Recipe>> getRecommendedRecipes(
    List<Recipe> allRecipes,
    String userId,
  ) async {
    if (_userId == null) {
      print('❌ User ID not set - recommendation service not initialized');
      throw Exception('RecommendationService not initialized with user ID');
    }

    try {
      print('\n📊 Starting recommendation process');
      print('👤 User: $_userId');
      print('📚 Total available recipes: ${allRecipes.length}');
      print('Using Python server: $_usePythonServer');

      // Get user's history and preferences
      final searchHistory = await getUserSearchHistory();
      final favoriteIngredients = await _getFavoriteIngredients();
      final lastLogin = await _getLastLoginTime();

      // Get liked recipes to ensure they're included in recommendations
      final likedRecipes = await _getLikedRecipes();
      print('✅ Found ${likedRecipes.length} liked recipes for user');

      // Try to get recommendations from Python server first
      if (_usePythonServer && ApiConfig.mlUrl.isNotEmpty) {
        try {
          print('\n🤖 Requesting recommendations from Python server');
          print('Python server URL: ${ApiConfig.mlUrl}');

          // Get recommendations from the Python server
          final response = await http
              .get(
                Uri.parse('${ApiConfig.mlUrl}/api/recommendations/$userId'),
                headers: {'Content-Type': 'application/json'},
              )
              .timeout(const Duration(seconds: 15));

          print('Python server response status: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            print('📊 Python server response: ${response.body}');

            if (data['exists'] == true) {
              if (data['error'] != null) {
                print('⚠️ Python server error: ${data['error']}');
                print('⚠️ Message: ${data['message']}');

                if (data['error'] == 'Invalid user vector') {
                  print(
                    'ℹ️ User vector not available, using content-based recommendations',
                  );
                  return await _getContentBasedRecommendations(
                    allRecipes,
                    await _getFavoriteIngredients(),
                  );
                }

                throw Exception(data['message']);
              }

              if (data['recommendations'] != null) {
                final recommendations = data['recommendations'] as List;
                print(
                  '✅ Received ${recommendations.length} recommendations from Python server',
                );

                // Convert recommendation IDs to Recipe objects
                final List<Recipe> recommendedRecipes = [];
                final Set<String> seenIds = {};

                for (var rec in recommendations) {
                  try {
                    final recipeId = rec['id']?.toString();
                    if (recipeId == null || seenIds.contains(recipeId))
                      continue;

                    final recipe = allRecipes.firstWhere(
                      (r) => r.id == recipeId,
                      orElse: () {
                        print('⚠️ Recipe $recipeId not found in allRecipes');
                        return allRecipes[0];
                      },
                    );

                    // Process ingredients if they're in tokenized format
                    if (rec['ingredients'] is List) {
                      final tokens =
                          (rec['ingredients'] as List)
                              .map((t) => t.toString())
                              .toList();
                      final ingredients = _reconstructIngredients(tokens);
                      if (ingredients.isNotEmpty) {
                        recipe.ingredients?.addAll(ingredients);
                      }
                    }

                    recommendedRecipes.add(recipe);
                    seenIds.add(recipeId);
                  } catch (e) {
                    print('❌ Error processing recommendation: $e');
                  }
                }

                if (recommendedRecipes.isNotEmpty) {
                  print(
                    '✅ Successfully processed ${recommendedRecipes.length} recommendations',
                  );
                  return recommendedRecipes;
                } else {
                  print(
                    '⚠️ No valid recommendations found in Python server response',
                  );
                  return await _getContentBasedRecommendations(
                    allRecipes,
                    await _getFavoriteIngredients(),
                  );
                }
              }
            }
          }
        } catch (e) {
          print('❌ Python recommendation error: $e');
          print('Falling back to content-based recommendations');
        }
      }

      // Fall back to content-based recommendations if Python server fails
      return await _getContentBasedRecommendations(
        allRecipes,
        favoriteIngredients,
      );
    } catch (e) {
      print('❌ Error in recommendation process: $e');
      // Fall back to random recommendations
      final random = Random();
      final randomRecipes = List<Recipe>.from(allRecipes);
      randomRecipes.shuffle(random);
      return randomRecipes.take(20).toList();
    }
  }

  // Get user's last login time
  static Future<String?> _getLastLoginTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('${_userId}_$_lastLoginKey');
    } catch (e) {
      print('❌ Error getting last login time: $e');
      return null;
    }
  }

  // Get favorite ingredients based on user interactions
  static Future<List<String>> _getFavoriteIngredients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ingredients =
          prefs.getStringList('${_userId}_$_favoriteIngredientsKey') ?? [];
      return ingredients;
    } catch (e) {
      print('❌ Error getting favorite ingredients: $e');
      return [];
    }
  }

  // Record user interaction with enhanced tracking
  static Future<void> recordInteraction(Recipe recipe) async {
    if (_userId == null) {
      print('❌ Cannot record interaction - user not initialized');
      throw Exception('RecommendationService not initialized with user ID');
    }

    try {
      print('\n📝 Recording user interaction');
      print('👤 User: $_userId');
      print('🍽️ Recipe: ${recipe.title} (${recipe.id})');

      // Track interaction on Python server
      if (_usePythonServer && ApiConfig.mlUrl.isNotEmpty) {
        try {
          await http.post(
            Uri.parse('${ApiConfig.mlUrl}/api/track'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'user_id': _userId,
              'recipe_id': recipe.id,
              'ingredients_used': recipe.ingredients ?? [],
            }),
          );
          print('✅ Interaction recorded on Python server');
        } catch (e) {
          print('❌ Failed to record interaction on Python server: $e');
        }
      }

      // Also update favorite ingredients
      if (recipe.ingredients != null && recipe.ingredients!.isNotEmpty) {
        await _updateFavoriteIngredients(recipe.ingredients!);
      }
    } catch (e) {
      print('❌ Error recording interaction: $e');
    }
  }

  // Update favorite ingredients based on interactions
  static Future<void> _updateFavoriteIngredients(
    List<String> newIngredients,
  ) async {
    if (_userId == null) {
      print('❌ Cannot update favorite ingredients - user not initialized');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentIngredients = await _getFavoriteIngredients();

      // Combine and get unique ingredients
      final Set<String> uniqueIngredients = {
        ...currentIngredients,
        ...newIngredients,
      };

      // Keep only the top 50 ingredients
      final ingredients = uniqueIngredients.take(50).toList();

      // Save with user-specific key
      final userKey = '${_userId}_$_favoriteIngredientsKey';
      await prefs.setStringList(userKey, ingredients);

      print(
        '✅ Updated favorite ingredients for user $_userId: ${ingredients.length} items',
      );
      print(
        '🥗 Current favorite ingredients: ${ingredients.take(5).join(", ")}${ingredients.length > 5 ? "..." : ""}',
      );
    } catch (e) {
      print('❌ Error updating favorite ingredients: $e');
    }
  }

  // Public method to update favorite ingredients
  static Future<void> updateFavoriteIngredients(
    List<String> ingredients,
  ) async {
    if (_userId == null) {
      print('❌ Cannot update favorite ingredients - user not initialized');
      return;
    }

    try {
      print('\n📝 Updating favorite ingredients');
      print('👤 User: $_userId');
      print('🥗 New ingredients count: ${ingredients.length}');

      await _updateFavoriteIngredients(ingredients);

      // Try to update on Python server if available
      if (_usePythonServer && ApiConfig.mlUrl.isNotEmpty) {
        try {
          final response = await http
              .post(
                Uri.parse('${ApiConfig.mlUrl}/api/preferences'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'user_id': _userId,
                  'favorite_ingredients': ingredients,
                }),
              )
              .timeout(const Duration(seconds: 5));

          print(
            '📡 Preferences updated on Python server: ${response.statusCode}',
          );
        } catch (e) {
          print('❌ Failed to update preferences on Python server: $e');
        }
      }

      // Update on Node.js server
      try {
        final response = await http
            .post(
              Uri.parse('${ApiConfig.baseUrl}/api/preferences'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${Auth().token}',
              },
              body: json.encode({
                'userId': _userId,
                'favoriteIngredients': ingredients,
              }),
            )
            .timeout(const Duration(seconds: 5));

        print('📡 Preferences updated on Node.js: ${response.statusCode}');
      } catch (e) {
        print('❌ Error updating preferences on Node.js: $e');
      }
    } catch (e) {
      print('❌ Error in updateFavoriteIngredients: $e');
    }
  }

  // Get user preferences
  static Future<Map<String, dynamic>> getUserPreferences() async {
    if (_userId == null) {
      throw Exception('RecommendationService not initialized with user ID');
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/users/$_userId'));

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to get user preferences: ${response.statusCode}',
        );
      }

      return json.decode(response.body);
    } catch (e) {
      print('Error getting user preferences: $e');
      rethrow;
    }
  }

  // Get user's search history
  static Future<List<String>> getUserSearchHistory() async {
    if (_userId == null) return [];

    try {
      final response = await http.get(
        Uri.parse('${Auth().baseUrl}/api/users/searches'),
        headers: Auth().authHeaders,
      );

      if (response.statusCode == 200) {
        final List<dynamic> searches = json.decode(response.body);
        return searches.cast<String>();
      }
      return [];
    } catch (e) {
      print('❌ Error fetching search history: $e');
      return [];
    }
  }

  // Helper method to reconstruct ingredients from tokens
  static List<String> _reconstructIngredients(List<String> tokens) {
    try {
      // Join tokens that were split incorrectly
      List<String> ingredients = [];
      StringBuffer currentIngredient = StringBuffer();

      for (var token in tokens) {
        // Clean the token
        var cleaned = token.replaceAll(RegExp(r"['\[\]]"), '').trim();
        if (cleaned.isEmpty) continue;

        // Check if token ends with a comma or is the last measurement unit
        if (cleaned.endsWith(',') ||
            RegExp(
              r'(tablespoons?|teaspoons?|cups?|pounds?|ounces?|grams?|ml|g|kg|oz|lb)$',
            ).hasMatch(cleaned)) {
          currentIngredient.write('$cleaned ');
          ingredients.add(currentIngredient.toString().trim());
          currentIngredient.clear();
        } else {
          // If it's a number or fraction, start a new ingredient
          if (RegExp(r'^\d+(/\d+)?$').hasMatch(cleaned) &&
              currentIngredient.isEmpty) {
            currentIngredient.write('$cleaned ');
          } else {
            currentIngredient.write('$cleaned ');
          }
        }
      }

      // Add any remaining ingredient
      if (currentIngredient.isNotEmpty) {
        ingredients.add(currentIngredient.toString().trim());
      }

      // Clean up the ingredients
      ingredients =
          ingredients
              .map((ing) {
                // Remove extra spaces and punctuation
                var cleaned = ing.replaceAll(RegExp(r'\s+'), ' ').trim();
                cleaned = cleaned.replaceAll(RegExp(r',+$'), '');
                return cleaned;
              })
              .where((ing) => ing.isNotEmpty)
              .toList();

      return ingredients;
    } catch (e) {
      print('❌ Error reconstructing ingredients: $e');
      return [];
    }
  }
}
