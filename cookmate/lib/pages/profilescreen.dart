import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:cookmate/authentication/auth.dart';
import 'package:cookmate/pages/signin.dart';
import 'package:cookmate/services/api_services.dart';
import 'package:cookmate/pages/homescreen.dart';
import 'package:cookmate/pages/detailrecipe.dart';
import 'package:cookmate/widgets/profile_picture.dart';
import 'package:cookmate/config/api_config.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Auth _auth = Auth();
  bool _isLoading = true;
  int _recipeCount = 0;
  int _likedCount = 0;
  List<Recipe> _userRecipes = [];
  List<Recipe> _likedRecipes = [];

  @override
  void initState() {
    super.initState();
    _loadUserStats();
    _loadLikedRecipesCount();
  }

  Future<void> _loadUserStats() async {
    try {
      final stats = await _auth.getUserStats();
      if (mounted) {
        setState(() {
          _recipeCount = stats['recipeCount'];
          _isLoading = false;
        });
      }
      print(
        'Loaded stats: Recipes: $_recipeCount, Liked: $_likedCount',
      ); // Debug log
    } catch (e) {
      print('Error loading stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadLikedRecipesCount() async {
    try {
      final likedRecipes = await ApiService.getLikedRecipes(_auth.userId!);
      if (mounted) {
        setState(() {
          _likedCount = likedRecipes.length;
          _likedRecipes = likedRecipes;
        });
      }
    } catch (e) {
      print('Error loading liked recipes for count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 40),
          Center(
            child: GestureDetector(
              onTap: () async {
                final hasProfile =
                    _auth.profileImageUrl != null &&
                    _auth.profileImageUrl!.isNotEmpty;
                final result = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasProfile)
                            ListTile(
                              leading: const Icon(Icons.photo_camera),
                              title: const Text('Change Profile Picture'),
                              onTap: () => Navigator.pop(context, 'change'),
                            ),
                          if (hasProfile)
                            ListTile(
                              leading: const Icon(Icons.delete),
                              title: const Text('Remove Profile Picture'),
                              onTap: () => Navigator.pop(context, 'remove'),
                            ),
                          if (!hasProfile)
                            ListTile(
                              leading: const Icon(Icons.upload),
                              title: const Text('Upload Profile Picture'),
                              onTap: () => Navigator.pop(context, 'upload'),
                            ),
                        ],
                      ),
                    );
                  },
                );
                if (result == 'change' || result == 'upload') {
                  // Pick image and upload
                  final picker = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                  );
                  if (picker != null) {
                    try {
                      await uploadProfilePicture(
                        File(picker.path),
                        _auth.token!,
                      );
                      await _auth.fetchAndUpdateUserInfo();
                      if (mounted) setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Profile picture updated'),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to upload profile picture: $e'),
                        ),
                      );
                    }
                  }
                } else if (result == 'remove') {
                  try {
                    await _auth.removeProfilePicture();
                    await _auth.fetchAndUpdateUserInfo();
                    if (mounted) setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profile picture removed')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to remove profile picture: $e'),
                      ),
                    );
                  }
                }
              },
              child: ProfilePicture(
                size: 120,
                imageUrl: _auth.profileImageUrl,
                onRemove: null, // Remove handled by menu now
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _auth.fullName ?? 'Guest User',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Edit Name',
                onPressed: () async {
                  final result = await showDialog<Map<String, String>>(
                    context: context,
                    builder: (context) {
                      final firstNameController = TextEditingController(
                        text: _auth.firstName ?? '',
                      );
                      final lastNameController = TextEditingController(
                        text: _auth.lastName ?? '',
                      );
                      return AlertDialog(
                        title: const Text('Edit Name'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: firstNameController,
                              decoration: const InputDecoration(
                                labelText: 'First Name',
                              ),
                            ),
                            TextField(
                              controller: lastNameController,
                              decoration: const InputDecoration(
                                labelText: 'Last Name',
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context, {
                                'firstName': firstNameController.text.trim(),
                                'lastName': lastNameController.text.trim(),
                              });
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      );
                    },
                  );
                  if (result != null &&
                      (result['firstName']?.isNotEmpty == true ||
                          result['lastName']?.isNotEmpty == true)) {
                    try {
                      await _auth.updateUserName(
                        firstName: result['firstName'],
                        lastName: result['lastName'],
                      );
                      await _auth.fetchAndUpdateUserInfo();
                      if (mounted) setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Name updated successfully'),
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update name: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          Text(
            _auth.email ?? 'No email',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatColumn('$_recipeCount', 'Recipes'),
              _buildStatColumn('$_likedCount', 'Liked'),
            ],
          ),
          const SizedBox(height: 16),
          const TabBarSection(),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label),
      ],
    );
  }
}

class TabBarSection extends StatefulWidget {
  const TabBarSection({Key? key}) : super(key: key);

  @override
  State<TabBarSection> createState() => _TabBarSectionState();
}

class _TabBarSectionState extends State<TabBarSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Recipe> _userRecipes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadUserRecipes();
  }

  @override
  void didChangeDependency() {
    super.didChangeDependencies();
    _loadUserRecipes(); // Refresh when tab changes
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<List<Recipe>> _filterRecipesWithValidImages(
    List<Recipe> recipes,
  ) async {
    List<Recipe> validRecipes = [];
    for (final recipe in recipes) {
      // Skip if image is null or empty
      if (recipe.imageUrl == null || recipe.imageUrl!.trim().isEmpty) {
        print('Filtered out recipe with empty image: \\${recipe.title}');
        continue;
      }
      final imageUrl = await ApiConfig.getImageUrl(recipe.imageUrl!);
      if (imageUrl.isNotEmpty) {
        validRecipes.add(recipe);
      } else {
        print('Filtered out recipe with missing image file: \\${recipe.title}');
      }
    }
    return validRecipes;
  }

  Future<void> _loadUserRecipes() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final rawRecipes = await Auth().getUserRecipes();
      final allRecipes =
          rawRecipes.map((json) => Recipe.fromJson(json)).toList();
      final filteredRecipes = await _filterRecipesWithValidImages(allRecipes);
      if (mounted) {
        setState(() {
          _userRecipes = filteredRecipes;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading user recipes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 1,
      child: Expanded(
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              indicatorColor: Colors.green,
              labelColor: Colors.green,
              unselectedLabelColor: Colors.grey,
              tabs: const [Tab(text: 'Recipes')],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildRecipeGrid()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeGrid() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userRecipes.isEmpty) {
      return const Center(child: Text('No recipes uploaded yet'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _userRecipes.length,
      itemBuilder: (context, index) {
        final recipe = _userRecipes[index];
        return RecipeCard(
          key: ValueKey(recipe.id),
          recipe: recipe,
          onDelete: () {
            setState(() {
              _userRecipes.remove(recipe);
            });
          },
        );
      },
    );
  }
}

class RecipeCard extends StatefulWidget {
  final Recipe recipe;
  final VoidCallback? onDelete;

  const RecipeCard({Key? key, required this.recipe, this.onDelete})
    : super(key: key);

  @override
  State<RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<RecipeCard> {
  bool _isLiked = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLikeStatus();
  }

  Future<void> _checkLikeStatus() async {
    final isLiked = await Auth().isRecipeLiked(widget.recipe.id);
    if (mounted) setState(() => _isLiked = isLiked);
  }

  Future<void> _toggleLike() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final liked = await Auth().toggleLikeRecipe(widget.recipe.id);
      if (mounted) setState(() => _isLiked = liked);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RecipeDetailPage(recipe: widget.recipe),
          ),
        );
      },
      onLongPress: () async {
        // Show delete confirmation dialog
        final shouldDelete = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Delete Recipe'),
                content: const Text(
                  'Are you sure you want to delete this recipe?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
        );

        if (shouldDelete == true && mounted) {
          try {
            final success = await Auth().deleteRecipe(widget.recipe.id);
            if (success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Recipe deleted successfully')),
              );
              // Refresh the current screen instead of pushing new one
              if (mounted) {
                setState(() {
                  // Trigger parent widget to refresh
                  widget.onDelete?.call();
                });
              }
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to delete recipe: $e')),
              );
            }
          }
        }
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: CachedNetworkImage(
                imageUrl: ApiConfig.getImageUrl(widget.recipe.imageUrl!),
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => Container(
                      height: 100,
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                errorWidget: (context, url, error) {
                  print(
                    'Error loading image: $error for path: ${widget.recipe.imageUrl}',
                  );
                  return Container(
                    height: 100,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        size: 30,
                        color: Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                widget.recipe.title ?? 'Untitled',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> uploadProfilePicture(File imageFile, String token) async {
  final userId = Auth().userId;
  final fileName =
      'profile_${userId}_${DateTime.now().millisecondsSinceEpoch}${imageFile.path.split('.').last.isNotEmpty ? "." + imageFile.path.split('.').last : ''}';
  final uri = Uri.parse('http://10.29.40.35:3000/api/upload/profile-picture');
  final request =
      http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['filename'] = fileName
        ..files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            filename: fileName,
          ),
        );

  final response = await request.send();

  if (response.statusCode == 200) {
    final respStr = await response.stream.bytesToString();
    print('Upload success: $respStr');
  } else {
    final respStr = await response.stream.bytesToString();
    print('Upload failed: $respStr');
    throw Exception('Failed to upload profile picture');
  }
}
