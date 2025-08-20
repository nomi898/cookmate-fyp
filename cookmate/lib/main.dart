import 'package:cookmate/pages/welcome.dart';
import 'package:flutter/material.dart';
import 'package:cookmate/config/api_config.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('\n🚀 Initializing app...');
  print('Platform: ${Platform.operatingSystem}');
  print('Is web: $kIsWeb');

  try {
    // Configure environment and server URLs
    print('\n🔧 Configuring environment and server URLs...');
    final configured = await ApiConfig.configureEnvironment();

    if (configured) {
      print('\n✅ Successfully configured server URLs:');
      print('Node.js server: ${ApiConfig.baseUrl}');
      print('Python server: ${ApiConfig.mlUrl}');

      // Test connection to both servers
      print('\n🔍 Testing connection to servers...');
      final nodeConnected = await ApiConfig.testConnection();
      print(
        'Node.js server connection: ${nodeConnected ? '✅ Success' : '❌ Failed'}',
      );

      // Try to connect to Python server
      try {
        final pythonUrl = ApiConfig.mlUrl;
        if (pythonUrl.isNotEmpty) {
          print('Testing Python server at: $pythonUrl');
          final response = await http
              .get(Uri.parse(pythonUrl))
              .timeout(const Duration(seconds: 5));
          print('Python server response: ${response.statusCode}');
          print(
            'Python server connection: ${response.statusCode >= 200 && response.statusCode < 500 ? '✅ Success' : '❌ Failed'}',
          );
        } else {
          print('Python server URL is empty, skipping connection test');
        }
      } catch (e) {
        print('❌ Python server connection test failed: $e');
        // Continue with the app even if Python server is not available
      }
    } else {
      print('\n❌ Failed to configure local servers');
      // Use local URLs as fallback
      ApiConfig.useLocalUrls();
      print('Using fallback local URLs:');
      print('Node.js server: ${ApiConfig.baseUrl}');
      print('Python server: ${ApiConfig.mlUrl}');
    }
  } catch (e) {
    print('\n❌ Error during initialization: $e');
    print('Using local URLs as fallback');
    ApiConfig.useLocalUrls();
    print('Node.js server: ${ApiConfig.baseUrl}');
    print('Python server: ${ApiConfig.mlUrl}');
  }

  print('\n🏁 App initialization complete, starting...');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CookMate',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          primary: const Color.fromRGBO(31, 204, 121, 1),
        ),
        useMaterial3: true,
      ),
      home: Scaffold(body: SafeArea(child: Welcome())),
    );
  }
}
