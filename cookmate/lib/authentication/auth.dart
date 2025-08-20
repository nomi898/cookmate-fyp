import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:device_info_plus/device_info_plus.dart';

class Auth {
  static final Auth _instance = Auth._internal();
  factory Auth() => _instance;

  Auth._internal() {
    _loadUserData(); // Initialize data when instance is created
  }

  String? _token;
  String? _userId;
  String? _firstName;
  String? _lastName;
  String? _email;
  String? _profileImageUrl;

  String get baseUrl => ApiConfig.baseUrl;

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  // Getters for user info
  bool get isAuthenticated => _token != null;
  bool get isLoggedIn => _token != null;
  String? get token => _token;
  String? get userId => _userId;
  String? get firstName => _firstName;
  String? get lastName => _lastName;
  String? get fullName =>
      _firstName != null && _lastName != null ? '$_firstName $_lastName' : null;
  String? get email => _email;
  String? get profileImageUrl => _profileImageUrl;

  Future<void> _initializeAuth() async {
    try {
      await _loadUserData();
    } catch (e) {
      print('Failed to load user data: $e');
      // Continue with null values if loading fails
    }
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');
      _userId = prefs.getString('userId');
      _firstName = prefs.getString('firstName');
      _lastName = prefs.getString('lastName');
      _email = prefs.getString('email');
      _profileImageUrl = prefs.getString('profileImageUrl');

      print('Loaded user data:');
      print('- Name: $_firstName $_lastName');
      print('- Email: $_email');
      print('- Profile Image: $_profileImageUrl');
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _saveUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_token != null) await prefs.setString('token', _token!);
      if (_userId != null) await prefs.setString('userId', _userId!);
      if (_firstName != null) await prefs.setString('firstName', _firstName!);
      if (_lastName != null) await prefs.setString('lastName', _lastName!);
      if (_email != null) await prefs.setString('email', _email!);
      if (_profileImageUrl != null) {
        await prefs.setString('profileImageUrl', _profileImageUrl!);
        print('Saved profile image URL: $_profileImageUrl');
      }
    } catch (e) {
      print('Error saving user data: $e');
    }
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    int maxRetries = 2;
    int currentRetry = 0;

    while (currentRetry <= maxRetries) {
      try {
        // Test connection first
        final isConnected = await testConnection();
        if (!isConnected) {
          if (Platform.isAndroid && await isEmulator()) {
            // If emulator connection fails, try local network
            print('Emulator connection failed, trying local network');
            ApiConfig.useLocalUrls();
            final localConnected = await testConnection();
            if (!localConnected) {
              throw Exception(
                'Could not connect to server. Please ensure the server is running.',
              );
            }
          } else {
            throw Exception(
              'Could not connect to server. Please ensure the server is running and check your network connection.',
            );
          }
        }

        print(
          'Attempting login for email: $email (Attempt ${currentRetry + 1}/${maxRetries + 1})',
        );
        print('Sending request to: $baseUrl/api/auth/login');

        final response = await http
            .post(
              Uri.parse('$baseUrl/api/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'email': email, 'password': password}),
            )
            .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

        print('Login response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['token'] == null) {
            throw Exception('Invalid response: missing token');
          }

          _token = data['token'];
          if (data['user'] != null) {
            final userData = data['user'];
            _userId = userData['_id'] ?? userData['id'];
            _firstName = userData['firstName'];
            _lastName = userData['lastName'];
            _email = userData['email'];
            _profileImageUrl =
                userData['profilePicture'] ?? userData['profileImageUrl'];
            await _saveUserData();
            print('Login successful');
            return;
          }
          throw Exception('Invalid response: missing user data');
        } else {
          final error = json.decode(response.body);
          throw Exception(error['message'] ?? 'Login failed');
        }
      } catch (e) {
        print(
          'Login error (Attempt ${currentRetry + 1}/${maxRetries + 1}): $e',
        );

        if (currentRetry >= maxRetries) {
          if (e.toString().contains('Could not connect to server')) {
            throw Exception(
              'Could not connect to server. Please ensure the server is running and check your network connection.',
            );
          } else if (e.toString().contains('Invalid credentials')) {
            throw Exception('Invalid email or password.');
          } else {
            throw Exception(e.toString());
          }
        }

        await Future.delayed(const Duration(seconds: 2));
        currentRetry++;
      }
    }
  }

  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        }),
      );

      print('Server response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 201) {
        // Store the user data in the Auth instance
        _firstName = firstName;
        _lastName = lastName;
        _email = email;
        await _saveUserData(); // Save to SharedPreferences
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Registration failed');
      }
    } on FormatException {
      throw Exception('Invalid server response');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/reset-password-request'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      if (response.statusCode == 200) {
        print('Password reset email sent');
      } else {
        final error = json.decode(response.body);
        print(
          'Reset email failed: ${response.statusCode} - ${error['message']}',
        );
        throw Exception(error['message'] ?? 'Failed to send reset email');
      }
    } catch (e) {
      print('Reset email error: $e');
      throw Exception('Failed to connect to server');
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/reset-password/$token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'password': newPassword}),
      );

      if (response.statusCode == 200) {
        print('Password reset successful');
      } else {
        final error = json.decode(response.body);
        print(
          'Password reset failed: ${response.statusCode} - ${error['message']}',
        );
        throw Exception(error['message'] ?? 'Failed to reset password');
      }
    } catch (e) {
      print('Password reset error: $e');
      throw Exception('Failed to connect to server');
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _token = null;
    _userId = null;
    _firstName = null;
    _lastName = null;
    _email = null;
    _profileImageUrl = null;
    print('User signed out and data cleared');
  }

  Future<Map<String, dynamic>> getUserStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/stats'),
        headers: authHeaders,
      );

      print('Stats response status: ${response.statusCode}');
      print('Stats response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'recipeCount': data['recipeCount'] ?? 0,
          'likedCount': data['likedCount'] ?? 0,
        };
      } else {
        print('Error response: ${response.body}');
        throw Exception('Failed to fetch user stats');
      }
    } catch (e) {
      print('Error fetching user stats: $e');
      return {'recipeCount': 0, 'likedCount': 0};
    }
  }

  Future<List<dynamic>> getUserRecipes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/recipes'),
        headers: authHeaders,
      );
      print('Recipes response: \\${response.statusCode}'); // Debug log
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch user recipes');
      }
    } catch (e) {
      print('Error fetching user recipes: $e');
      return [];
    }
  }

  Future<List<dynamic>> getLikedRecipes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/users/liked-recipes'),
        headers: authHeaders,
      );
      print('Liked recipes response: \\${response.statusCode}'); // Debug log
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch liked recipes');
      }
    } catch (e) {
      print('Error fetching liked recipes: $e');
      return [];
    }
  }

  Future<bool> isRecipeLiked(String recipeId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/recipes/$recipeId/is-liked'),
        headers: authHeaders,
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

  Future<bool> toggleLikeRecipe(String recipeId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/recipes/$recipeId/toggle-like'),
        headers: authHeaders,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['liked'] ?? false;
      }
      return false;
    } catch (e) {
      print('Error toggling like: $e');
      return false;
    }
  }

  Future<void> updateProfileImageUrl(String newImageUrl) async {
    _profileImageUrl = newImageUrl;
    await _saveUserData();
    print('Updated profile image URL: $newImageUrl');
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Send Google credentials to your backend
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': googleAuth.idToken,
          'email': googleUser.email,
          'firstName': googleUser.displayName?.split(' ').first,
          'lastName': googleUser.displayName?.split(' ').last,
          'profilePicture': googleUser.photoUrl,
        }),
      );

      print(
        'Google sign in response: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];

        if (data['user'] != null) {
          final userData = data['user'];
          _userId = userData['_id'];
          _firstName = userData['firstName'];
          _lastName = userData['lastName'];
          _email = userData['email'];
          _profileImageUrl = userData['profilePicture'];
          await _saveUserData();
          print('Google sign in successful - Profile: $_profileImageUrl');
        }
      } else {
        throw Exception('Google sign in failed');
      }
    } catch (e) {
      print('Google sign in error: $e');
      throw Exception('Failed to sign in with Google');
    }
  }

  Map<String, String> get authHeaders => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<bool> deleteRecipe(String recipeId) async {
    try {
      print('Attempting to delete recipe: $recipeId');
      print('Using headers: $authHeaders');
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/recipes/$recipeId'),
        headers: authHeaders,
      );
      print('Delete response status: ${response.statusCode}');
      print('Delete response body: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting recipe: $e');
      return false;
    }
  }

  // Test connection to backend
  Future<bool> testConnection() async {
    try {
      print('Testing connection to server at: $baseUrl');

      // Try root endpoint first
      try {
        final rootResponse = await http
            .get(Uri.parse(baseUrl))
            .timeout(const Duration(seconds: 5));

        if (rootResponse.statusCode == 200) {
          print('✅ Successfully connected to server');
          return true;
        }
      } catch (e) {
        print('Root endpoint test failed: $e');
      }

      // Try login endpoint as fallback
      final loginResponse = await http
          .get(Uri.parse('$baseUrl/api/auth/login'))
          .timeout(const Duration(seconds: 5));

      // Even a 401 (unauthorized) means the server is up
      if (loginResponse.statusCode == 200 || loginResponse.statusCode == 401) {
        print('✅ Successfully connected to server');
        return true;
      }

      print('❌ Failed to connect to server: ${loginResponse.statusCode}');
      return false;
    } catch (e) {
      print('❌ Connection test failed: $e');
      if (e.toString().contains('timeout')) {
        print('Connection test timed out - server may be slow or unavailable');
      } else if (e.toString().contains('Connection refused')) {
        print('Connection refused - server may not be running');
      }
      return false;
    }
  }

  // Add isEmulator method to Auth class
  Future<bool> isEmulator() async {
    if (Platform.isAndroid) {
      try {
        final deviceInfo = await DeviceInfoPlugin().androidInfo;
        return !deviceInfo.isPhysicalDevice;
      } catch (e) {
        print('Error checking if device is emulator: $e');
        return false;
      }
    }
    return false;
  }

  Future<void> reloadUserData() async {
    await _loadUserData();
  }

  /// Update user's first and/or last name
  Future<void> updateUserName({String? firstName, String? lastName}) async {
    if (_token == null) throw Exception('Not authenticated');
    final body = <String, String>{};
    if (firstName != null) body['firstName'] = firstName;
    if (lastName != null) body['lastName'] = lastName;
    if (body.isEmpty) throw Exception('No name fields provided');
    final response = await http.patch(
      Uri.parse('$baseUrl/api/users/me'),
      headers: authHeaders,
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _firstName = data['firstName'] ?? _firstName;
      _lastName = data['lastName'] ?? _lastName;
      await _saveUserData();
    } else {
      throw Exception('Failed to update name: \\${response.body}');
    }
  }

  /// Remove user's profile picture
  Future<void> removeProfilePicture() async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.delete(
      Uri.parse('$baseUrl/api/users/me/profile-picture'),
      headers: authHeaders,
    );
    if (response.statusCode == 200) {
      _profileImageUrl = null;
      await _saveUserData();
    } else {
      throw Exception('Failed to remove profile picture: \\${response.body}');
    }
  }

  /// Fetch latest user info from backend and update local fields
  Future<void> fetchAndUpdateUserInfo() async {
    if (_token == null) throw Exception('Not authenticated');
    final response = await http.get(
      Uri.parse('$baseUrl/api/users/me'),
      headers: authHeaders,
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _userId = data['_id'] ?? data['id'] ?? _userId;
      _firstName = data['firstName'] ?? _firstName;
      _lastName = data['lastName'] ?? _lastName;
      _email = data['email'] ?? _email;
      _profileImageUrl =
          data['profilePicture'] ?? data['profileImageUrl'] ?? _profileImageUrl;
      await _saveUserData();
    } else {
      throw Exception('Failed to fetch user info: \\${response.body}');
    }
  }
}
