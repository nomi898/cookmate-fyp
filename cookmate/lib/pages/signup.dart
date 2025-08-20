import 'package:cookmate/pages/signin.dart';
import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:cookmate/authentication/auth.dart';

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUp> {
  bool _isPasswordVisible = false;
  String _password = '';
  bool _isLengthValid = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;
  String? _errorMessage = '';
  bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  void _validatePassword(String value) {
    setState(() {
      _password = value;
      _isLengthValid = value.length >= 8;
      _hasNumber = value.contains(RegExp(r'\d'));
      _hasSpecialChar = value.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  bool _isValidEmail(String email) {
    return email.endsWith('@gmail.com') || email.endsWith('@yahoo.com');
  }

  Future<void> _signUpWithEmailAndPassword() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    // Validate all fields
    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Please fill in all fields';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_isValidEmail(_emailController.text.trim())) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Email is not valid';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email is not valid'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await Auth().createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
      );

      // Ensure user data is loaded for the next screen
      await Auth().reloadUserData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Please sign in.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SignIn()),
        );
      }
    } catch (e) {
      if (mounted) {
        String message = e.toString();
        if (message.contains('Exception:')) {
          message = message.split('Exception:')[1].trim();
        }
        setState(() => _errorMessage = message);
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
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Widget _entryField(
    String title,
    TextEditingController controller, {
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !_isPasswordVisible,
      onChanged: isPassword ? _validatePassword : null,
      decoration: InputDecoration(
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _errorMessageWidget() {
    return Text(
      _errorMessage == '' ? '' : 'Oops! $_errorMessage',
      style: const TextStyle(color: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => SignIn()),
            );
          },
          icon: const Icon(Icons.arrow_back_ios_new),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                "Welcome!",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
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
            // First Name field
            _entryField("First Name", _firstNameController),
            const SizedBox(height: 20),
            // Last Name field
            _entryField("Last Name", _lastNameController),
            const SizedBox(height: 20),
            // Email field
            _entryField("Email", _emailController),
            const SizedBox(height: 20),
            // Password field
            _entryField("Password", _passwordController, isPassword: true),
            const SizedBox(height: 10),
            const Text(
              "Your Password must contain:",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  _isLengthValid ? Icons.check_circle : Icons.cancel,
                  color: _isLengthValid ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text("At least 8 characters"),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  _hasNumber ? Icons.check_circle : Icons.cancel,
                  color: _hasNumber ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text("Contains a number"),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Icon(
                  _hasSpecialChar ? Icons.check_circle : Icons.cancel,
                  color: _hasSpecialChar ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Text("Contains a special character"),
              ],
            ),
            const SizedBox(height: 20),
            _errorMessageWidget(),
            ElevatedButton(
              onPressed:
                  _isLengthValid && _hasNumber && _hasSpecialChar
                      ? _signUpWithEmailAndPassword
                      : null, // Disable button if conditions aren't met
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Center(
                child: Text(
                  "Sign Up",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
