import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';

class ApiConfig {
  static const int timeoutSeconds = 15;

  // Default server URLs
  static String _nodeServerUrl = '';
  static String _pythonServerUrl = '';

  // MacBook's IP and ports
  static const String macbookIP =
      // '192.168.18.20';
      '10.29.40.35'; // Updated to your actual IP address
  //'192.168.18.183';
  static const int nodePort = 3000;
  static const int pythonPort = 5002;

  // Local network URLs (will be set dynamically)
  static String localNodeUrl = 'http://$macbookIP:$nodePort';
  static String localPythonUrl = 'http://$macbookIP:$pythonPort';

  // Emulator URLs
  static const String emulatorNodeUrl = 'http://10.0.2.2:3000';
  static const String emulatorPythonUrl = 'http://10.0.2.2:5000';

  // Common local IP patterns to try
  static const List<String> commonIpPatterns = [
    '192.168.18.', // Your network subnet
    '192.168.1.', // Common router pattern
    '192.168.0.', // Alternative router pattern
    '10.0.0.', // Another common pattern
  ];

  // Server configuration
  static const String _computerIP =
      // '192.168.18.20'; //computer ip
      '10.29.40.35'; // Updated to match your actual IP
  static const int _nodePort = 3000; // Node.js server port
  static const int _pythonPort = 5002; // Flask server port

  // Node.js server URL
  static String get nodeServerUrl => 'http://10.29.40.35:3000';

  // Restore pythonServerUrl getter
  static String get pythonServerUrl {
    if (Platform.isAndroid) {
      return 'http://$_computerIP:$_pythonPort';
    } else if (Platform.isIOS) {
      if (_isSimulator()) {
        return 'http://localhost:$_pythonPort';
      } else {
        return 'http://$_computerIP:$_pythonPort';
      }
    }
    return 'http://localhost:$_pythonPort';
  }

  // For backward compatibility
  static String get baseUrl => nodeServerUrl;

  static String get mlUrl {
    const port = '5002'; // Updated to match Python server port
    return Platform.isAndroid
        ? 'http://192.168.18.183:$port' // Updated to match macbookIP
        : 'http://localhost:$port';
  }

  // Configure URLs for a specific environment
  static Future<bool> configureEnvironment() async {
    if (kIsWeb) {
      print('Running on web platform - using local URLs');
      useLocalUrls();
      return true;
    }

    try {
      print('Configuring environment...');
      print('Platform: ${Platform.operatingSystem}');

      // For iOS simulator, use localhost
      if (Platform.isIOS) {
        setNodeServerUrl('http://localhost:3000');
        setPythonServerUrl('http://localhost:5000');
        return true;
      }

      // For iOS devices, always use MacBook IP
      if (Platform.isIOS) {
        print('iOS device detected - using MacBook IP');
        useLocalUrls(); // This will use macbookIP
        final connected = await testConnection();
        if (connected) {
          print('Successfully connected to MacBook server');
          return true;
        }
        print('Failed to connect to MacBook server');
      }

      // For Android emulator
      if (Platform.isAndroid && await _isEmulator()) {
        print('Running on Android emulator - using emulator URLs');
        useEmulatorUrls();
        return await testConnection();
      }

      // Try saved URLs first
      final savedUrlsWork = await _tryUseSavedUrls();
      if (savedUrlsWork) {
        print('Successfully using saved URLs');
        return true;
      }

      // For physical devices or iOS simulator
      return await _tryLocalNetworkUrls();
    } catch (e) {
      print('Error during environment configuration: $e');
      print('Using default local URLs');
      useLocalUrls();
      return true;
    }
  }

  // Try to find and connect to local network server
  static Future<bool> _tryLocalNetworkUrls() async {
    print('Attempting to find local network server...');

    // Get device's WiFi IP
    String? deviceIP = await _getDeviceIP();
    if (deviceIP != null) {
      print('Device IP: $deviceIP');

      // Create list of IPs to try
      List<String> ipToTry = [];

      // Add MacBook IP first (highest priority)
      ipToTry.add(macbookIP);
      print('Added MacBook IP to try list: $macbookIP');

      // Add IPs based on device's network
      final ipParts = deviceIP.split('.');
      if (ipParts.length == 4) {
        // Try router IP
        final routerIP = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.1';
        ipToTry.add(routerIP);
        print('Added router IP to try list: $routerIP');

        // Try some IPs in the same subnet
        for (int i = 2; i <= 10; i++) {
          // Increased range from 5 to 10
          final subnetIP = '${ipParts[0]}.${ipParts[1]}.${ipParts[2]}.$i';
          ipToTry.add(subnetIP);
          print('Added subnet IP to try list: $subnetIP');
        }
      }

      // Try common patterns
      for (String pattern in commonIpPatterns) {
        if (pattern.endsWith('.')) {
          // For patterns ending with dot, try a few IPs
          for (int i = 1; i <= 10; i++) {
            // Increased range from 5 to 10
            final patternIP = '$pattern$i';
            ipToTry.add(patternIP);
            print('Added pattern IP to try list: $patternIP');
          }
        } else {
          ipToTry.add(pattern);
          print('Added pattern to try list: $pattern');
        }
      }

      // Remove duplicates
      ipToTry = ipToTry.toSet().toList();
      print('Total unique IPs to try: ${ipToTry.length}');

      // Try each IP
      for (String ip in ipToTry) {
        print('\nTrying IP: $ip');
        if (await _tryConnection(ip)) {
          print('Successfully connected to server at $ip');
          setNodeServerUrl('http://$ip:$nodePort');
          setPythonServerUrl('http://$ip:$pythonPort');
          await _saveServerUrls();
          return true;
        }
      }
    } else {
      print('Could not determine device IP address');
    }

    print('No local servers found, using default local URLs');
    useLocalUrls();
    return true;
  }

  // Test connection to a specific IP
  static Future<bool> _tryConnection(String ip) async {
    try {
      final nodeUrl = 'http://$ip:$nodePort';
      print('Testing connection to: $nodeUrl');

      final response = await http
          .get(Uri.parse(nodeUrl))
          .timeout(
            const Duration(seconds: 5),
          ); // Increased timeout from 2 to 5 seconds

      print('Connection test response: ${response.statusCode}');
      return response.statusCode == 200 || response.statusCode == 404;
    } catch (e) {
      print('Failed to connect to $ip: $e');
      return false;
    }
  }

  // Get device's WiFi IP address
  static Future<String?> _getDeviceIP() async {
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      print('Error getting device IP: $e');
      return null;
    }
  }

  // Check if running on emulator
  static Future<bool> _isEmulator() async {
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

  // Try to use previously saved URLs
  static Future<bool> _tryUseSavedUrls() async {
    try {
      await loadSavedUrls();
      if (_nodeServerUrl.isNotEmpty && _pythonServerUrl.isNotEmpty) {
        return await testConnection();
      }
    } catch (e) {
      print('Error trying saved URLs: $e');
    }
    return false;
  }

  // Setter methods to update URLs at runtime
  static void setNodeServerUrl(String url) {
    _nodeServerUrl = url;
    _saveServerUrls(); // Save the new URL
  }

  static void setPythonServerUrl(String url) {
    _pythonServerUrl = url;
    _saveServerUrls(); // Save the new URL
  }

  // Save current URLs to SharedPreferences
  static Future<void> _saveServerUrls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('node_server_url', _nodeServerUrl);
      await prefs.setString('python_server_url', _pythonServerUrl);
    } catch (e) {
      print('Error saving server URLs: $e');
    }
  }

  // Load saved URLs from SharedPreferences
  static Future<void> loadSavedUrls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _nodeServerUrl = prefs.getString('node_server_url') ?? _nodeServerUrl;
      _pythonServerUrl =
          prefs.getString('python_server_url') ?? _pythonServerUrl;
    } catch (e) {
      print('Error loading saved URLs: $e');
    }
  }

  // Switch to local URLs
  static void useLocalUrls() {
    setNodeServerUrl('http://localhost:3000');
    setPythonServerUrl('http://localhost:5000');
  }

  // Switch to emulator URLs
  static void useEmulatorUrls() {
    setNodeServerUrl(emulatorNodeUrl);
    setPythonServerUrl(emulatorPythonUrl);
  }

  // Helper for image URLs
  static String getImageUrl(String imagePath) {
    if (imagePath.startsWith('http')) {
      return imagePath;
    }
    // Prepend /uploads/ if not already present
    if (!imagePath.startsWith('/')) {
      imagePath = '/uploads/' + imagePath;
    }
    return baseUrl + imagePath;
  }

  // Helper to detect if running in simulator
  static bool _isSimulator() {
    if (Platform.isIOS) {
      return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
          Platform.environment.containsKey('SIMULATOR_HOST_HOME');
    }
    return false;
  }

  // Test connection with timeout and retry
  static Future<bool> testConnection() async {
    try {
      // Test Node.js server
      final nodeResponse = await http
          .get(Uri.parse('$nodeServerUrl/api/health'))
          .timeout(const Duration(seconds: 5));

      // Test Python server
      final pythonResponse = await http
          .get(Uri.parse('$pythonServerUrl/api/health'))
          .timeout(const Duration(seconds: 5));

      return nodeResponse.statusCode == 200 && pythonResponse.statusCode == 200;
    } catch (e) {
      print('Connection test failed: $e');
      return false;
    }
  }

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Access-Control-Allow-Origin': '*',
  };
}
