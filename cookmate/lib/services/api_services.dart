import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cookmate/pages/homescreen.dart';
import 'dart:io';
import 'package:cookmate/authentication/auth.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:cookmate/utils/events.dart';

class ApiService {
  final String baseUrl = ApiConfig.baseUrl;

  static Future<List<Recipe>> searchRecipes(String query) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${Auth().baseUrl}/api/recipes/search?query=${Uri.encodeComponent(query)}',
        ),
        headers: Auth().authHeaders,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Recipe.fromJson(json)).toList();
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Search failed: ${e.toString().split('\n')[0]}');
    }
  }

  static Future<List<String>> getRecentSearches(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${Auth().baseUrl}/api/users/$userId/searches'),
        headers: Auth().authHeaders,
      );

      if (response.statusCode == 200) {
        final List<dynamic> rawData = json.decode(response.body);

        // Sort the data by timestamp in descending order (newest first)
        rawData.sort((a, b) {
          final DateTime timeA = DateTime.parse(a['timestamp'].toString());
          final DateTime timeB = DateTime.parse(b['timestamp'].toString());
          return timeB.compareTo(timeA); // Descending order
        });

        // Extract queries and remove any malformed data
        final queries =
            rawData
                .map((item) {
                  if (item is Map<String, dynamic>) {
                    return item['query']?.toString() ?? '';
                  }
                  return '';
                })
                .where((query) => query.isNotEmpty)
                .toList();

        // Remove duplicates and ensure only the last 10 unique searches are kept
        final uniqueQueries = <String>[];
        for (final query in queries) {
          if (!uniqueQueries.contains(query)) {
            uniqueQueries.add(query);
            if (uniqueQueries.length == 10) break;
          }
        }

        return uniqueQueries;
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Load failed: ${e.toString().split('\n')[0]}');
    }
  }

  static Future<void> saveSearch(String userId, String query) async {
    try {
      // First get current searches to check count
      final currentSearches = await getRecentSearches(userId);

      // If we already have 7 searches, delete the oldest one
      if (currentSearches.length >= 10) {
        // Changed from 5 to 7
        final oldestQuery = currentSearches.last;
        // You might need to implement a deleteSearch endpoint in your API
        // await deleteSearch(userId, oldestQuery);
      }

      // Save the new search
      final response = await http.post(
        Uri.parse('${Auth().baseUrl}/api/users/$userId/searches'),
        headers: Auth().authHeaders,
        body: json.encode({'query': query}),
      );

      if (response.statusCode != 201) {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Save failed: ${e.toString().split('\n')[0]}');
    }
  }

  Future<void> someApiCall() async {
    final url = '$baseUrl/your-endpoint';
    // Use the url in your http calls
    // Example:
    // final response = await http.get(Uri.parse(url));
  }

  static Future<List<Recipe>> getLikedRecipes(String userId) async {
    try {
      print('Loading liked recipes for user: $userId');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/users/$userId/liked-recipes'),
        headers: {...Auth().authHeaders, 'Content-Type': 'application/json'},
      );

      print('Get liked recipes response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final recipes = data.map((json) => Recipe.fromJson(json)).toList();
        print('Loaded ${recipes.length} liked recipes');
        return recipes;
      } else {
        throw Exception('Failed to load liked recipes');
      }
    } catch (e) {
      print('Error in getLikedRecipes: $e');
      throw Exception('Failed to load liked recipes');
    }
  }

  static Future<void> unlikeRecipe(String recipeId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/likes/$recipeId/toggle-like'),
        headers: {...Auth().authHeaders, 'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        print('Unlike recipe failed with status: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('Failed to unlike recipe');
      }

      await Future.delayed(Duration(milliseconds: 250));
      eventBus.fire(LikeUpdatedEvent());
    } catch (e) {
      print('Error unliking recipe: $e');
      throw Exception('Failed to unlike recipe');
    }
  }

  static Future<bool> isRecipeLiked(String recipeId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/recipes/$recipeId/is-liked'),
        headers: Auth().authHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['isLiked'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error checking like status: $e');
      return false;
    }
  }

  static Future<void> likeRecipe(String recipeId) async {
    try {
      print('Liking recipe: $recipeId');
      print('User ID for like: ${Auth().userId}');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/likes/$recipeId/toggle-like'),
        headers: {...Auth().authHeaders, 'Content-Type': 'application/json'},
      );

      print('Like recipe response status: ${response.statusCode}');
      print('Like recipe response body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Failed to like recipe');
      }

      await Future.delayed(Duration(milliseconds: 250));
      eventBus.fire(LikeUpdatedEvent());
    } catch (e) {
      print('Error liking recipe: $e');
      throw Exception('Failed to like recipe');
    }
  }
}
