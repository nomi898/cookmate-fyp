import 'package:cookmate/pages/homescreen.dart';
import 'package:cookmate/widgets/loadingwidget.dart';
import 'package:cookmate/pages/signup.dart';
import 'package:cookmate/widgets/resetpassword.dart';
import 'package:flutter/material.dart';
import 'package:cookmate/authentication/auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignIn extends StatefulWidget {
  SignIn({super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  bool _isPasswordVisible = false;
  String? errorMessage = '';
  bool _isLoading = false; // State to track loading animation
  final TextEditingController _controllerEmail = TextEditingController();
  final TextEditingController _controllerPassword = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _rememberMe = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email');
      final savedPassword = prefs.getString('saved_password');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (mounted &&
          savedEmail != null &&
          savedPassword != null &&
          rememberMe) {
        setState(() {
          _controllerEmail.text = savedEmail;
          _controllerPassword.text = savedPassword;
          _rememberMe = true;
        });
      }
    } catch (e) {
      print('Error loading saved credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('saved_email', _controllerEmail.text);
        await prefs.setString('saved_password', _controllerPassword.text);
        await prefs.setBool('remember_me', true);
        print('Credentials saved successfully');
      } else {
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
        await prefs.setBool('remember_me', false);
        print('Credentials removed');
      }
    } catch (e) {
      print('Error saving credentials: $e');
    }
  }

  Future<void> signInEmailAndPassword() async {
    if (_formKey.currentState == null) {
      print('Form key current state is null');
      return;
    }

    if (!_formKey.currentState!.validate()) {
      print('Form validation failed');
      return;
    }

    setState(() {
      _isLoading = true;
      errorMessage = '';
    });

    try {
      print('Attempting to sign in with email: ${_controllerEmail.text}');

      // Show a loading dialog with a message about potential retries
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Logging in...', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text(
                    'This may take a few moments. The app will automatically retry if needed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          },
        );
      }

      await Auth().signInWithEmailPassword(
        email: _controllerEmail.text.trim(),
        password: _controllerPassword.text,
      );

      // Reload user data
      await Auth().reloadUserData();

      // Close the loading dialog if it's still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      print('Sign in successful, saving credentials if remember me is checked');
      if (mounted) {
        await _saveCredentials();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      print('Sign in error: $e');

      // Close the loading dialog if it's still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Show a more detailed error message
        String errorMessage = e.toString();
        if (errorMessage.contains('Failed to connect') ||
            errorMessage.contains('timeout') ||
            errorMessage.contains('Connection refused')) {
          errorMessage =
              'Could not connect to the server. Please check your internet connection and try again.';
        } else if (errorMessage.contains('Invalid credentials')) {
          errorMessage = 'Invalid email or password. Please try again.';
        } else if (errorMessage.contains('Internal server error')) {
          errorMessage = 'Server error. Please try again later.';
        } else if (errorMessage.contains('Exception:')) {
          // Extract the actual error message from the exception
          errorMessage = errorMessage.split('Exception:')[1].trim();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      errorMessage = '';
    });

    try {
      await Auth().signInWithGoogle();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      String message = e.toString();
      if (message.contains('Exception:')) {
        message = message.split('Exception:')[1].trim();
      }

      if (mounted) {
        setState(() {
          errorMessage = message;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _entryField(
    String title,
    TextEditingController controller, {
    bool isPassword = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        labelText: title,
        prefixIcon: Icon(isPassword ? Icons.lock : Icons.email),
        suffixIcon:
            isPassword
                ? IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                )
                : null,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your $title';
        }
        if (title == 'Email' && !value.contains('@')) {
          return 'Please enter a valid email address';
        }
        if (title == 'Password' && value.length < 6) {
          return 'Password must be at least 6 characters';
        }
        return null;
      },
    );
  }

  Widget _errorMessage() {
    return Text(
      errorMessage == '' ? '' : 'Oops! Invalid Credentials',
      style: const TextStyle(color: Colors.red),
    );
  }

  Widget _loginButton() {
    return ElevatedButton(
      onPressed: signInEmailAndPassword,
      style: ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).primaryColor,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: const Center(
        child: Text(
          "Login",
          style: TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    // crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          "Welcome Back!",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Center(
                        child: Text(
                          "Please enter your account here",
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 30),
                      _entryField('Email', _controllerEmail),
                      const SizedBox(height: 20),
                      _entryField(
                        'Password',
                        _controllerPassword,
                        isPassword: true,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                              ),
                              const Text('Remember Me'),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              resetpassword().ResetPassword(context);
                            },
                            child: const Text(
                              "Forgot password?",
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _errorMessage(),
                      _loginButton(),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: () async {
                          // Clear any user data to ensure guest session
                          await Auth().signOut();
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const HomeScreen(),
                              ),
                            );
                          }
                        },
                        child: const Text("Skip"),
                      ),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have any account? "),
                          TextButton(
                            onPressed: () {
                              // Navigate to SignUp screen
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SignUp(),
                                ),
                              );
                            },
                            child: const Text("Sign Up"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_isLoading)
          const Align(
            alignment: Alignment.bottomCenter,
            child: LoadingWidget(message: 'Signing in...'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _controllerEmail.dispose();
    _controllerPassword.dispose();
    super.dispose();
  }
}
