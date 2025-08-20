import 'package:cookmate/pages/homescreen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:http_parser/http_parser.dart';
import 'package:cookmate/authentication/auth.dart';
import 'package:cookmate/config/api_config.dart';

class UploadRecipeScreen extends StatefulWidget {
  const UploadRecipeScreen({Key? key}) : super(key: key);

  @override
  State<UploadRecipeScreen> createState() => _UploadRecipeScreenState();
}

class _UploadRecipeScreenState extends State<UploadRecipeScreen> {
  final TextEditingController _titleController = TextEditingController();
  final List<TextEditingController> _ingredientControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  final TextEditingController _stepsController = TextEditingController();
  File? _imageFile;
  bool _isUploading = false;

  @override
  void dispose() {
    _titleController.dispose();
    for (var controller in _ingredientControllers) {
      controller.dispose();
    }
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _imageFile = File(image.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/upload'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          _imageFile!.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        throw Exception('Upload failed with status: ${response.statusCode}');
      }

      final jsonData = jsonDecode(response.body);
      return jsonData['imageUrl'];
    } catch (e) {
      return null;
    }
  }

  Future<void> _uploadRecipe() async {
    if (_titleController.text.isEmpty || _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final String? imageUrl = await _uploadImage();
      if (imageUrl == null) throw Exception('Failed to upload image');

      // Split ingredients by comma instead of newline
      final List<String> ingredients =
          _ingredientControllers[0].text
              .split(',')
              .map((ingredient) => ingredient.trim())
              .where((ingredient) => ingredient.isNotEmpty)
              .toList();

      final recipeData = {
        'Title': _titleController.text.trim(),
        'Cleaned_Ingredients': ingredients,
        'Instructions': _stepsController.text.trim(),
        'image': imageUrl,
        'userId': Auth().userId,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/recipes'),
        headers: {'Content-Type': 'application/json', ...Auth().authHeaders},
        body: jsonEncode(recipeData),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        _showSuccessDialog(context);
      } else {
        throw Exception('Failed to upload recipe: ${response.statusCode}');
      }
    } catch (e) {
      print('Error uploading recipe: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload recipe: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomeScreen()),
            );
          },
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.red, fontSize: 15),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      _imageFile != null
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_imageFile!, fit: BoxFit.cover),
                          )
                          : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 40,
                                ),
                                SizedBox(height: 8),
                                Text('Add Cover Photo'),
                                Text('(up to 12 Mb)'),
                              ],
                            ),
                          ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Food Name',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(hintText: 'Enter food name'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ingredients',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextField(
                controller: _ingredientControllers[0],
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter ingredients (separated by commas)',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Steps',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextField(
                controller: _stepsController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Enter cooking steps',
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _uploadRecipe,
                  child:
                      _isUploading
                          ? const CircularProgressIndicator()
                          : const Text('Upload Recipe'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.celebration_outlined, size: 50, color: Colors.green),
                SizedBox(height: 16),
                Text(
                  'Upload Success',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                SizedBox(height: 8),
                Text(
                  'Your recipe has been uploaded, you can see it on your profile.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HomeScreen(),
                      ),
                    );
                  },
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
    );
  }
}
