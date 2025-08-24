import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart'; 
import 'config_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  
  void _switchAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
  }

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    setState(() { _isLoading = true; });

    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          data: {'full_name': _usernameController.text.trim()},
        );
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration successful! Please check your email for verification.')),
          );
        }
      }
    } on AuthException catch (error) {
      _showErrorDialog(error.message);
    } catch (error) {
      _showErrorDialog('An unexpected error occurred.');
    }

    if (mounted) {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _isLoading = true; });
    try {

      final webClientId = ConfigService.instance.googleWebClientId;
      final iosClientId = ConfigService.instance.googleIosClientId;

      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId: iosClientId,
        serverClientId: webClientId,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() { _isLoading = false; });
        return;
      }
      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) throw 'No Google Access Token found.';
      if (idToken == null) throw 'No Google ID Token found.';

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

    } catch (error) {
      _showErrorDialog(error.toString());
    }
    if(mounted) setState(() { _isLoading = false; });
  }


  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: const Text('Okay'),
            onPressed: () { Navigator.of(ctx).pop(); },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            _buildAuthForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 30, right: 30, bottom: 30),
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(50),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.directions_walk, color: Colors.white, size: 40),
          const SizedBox(height: 20),
          Text(
            _isLogin ? 'Welcome Back!' : 'Create Account',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isLogin ? 'Sign in to continue' : 'Sign up to get started',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAuthForm() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildToggleButtons(),
            const SizedBox(height: 32),
            if (!_isLogin) _buildTextField(_usernameController, 'Username', Icons.person_outline),
            if (!_isLogin) const SizedBox(height: 16),
            _buildTextField(_emailController, 'Email', Icons.email_outlined),
            const SizedBox(height: 16),
            _buildTextField(_passwordController, 'Password', Icons.lock_outline, isPassword: true),
            if (!_isLogin) const SizedBox(height: 16),
            if (!_isLogin) _buildTextField(_confirmPasswordController, 'Confirm Password', Icons.lock_outline, isPassword: true, isConfirm: true),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: _submitAuth,
                child: Text(_isLogin ? 'Login' : 'Register'),
              ),
            if (_isLogin) _buildSocialLogin(),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        _buildAuthModeSwitch('Login', _isLogin),
        const SizedBox(width: 20),
        _buildAuthModeSwitch('Register', !_isLogin),
      ],
    );
  }

  Widget _buildAuthModeSwitch(String title, bool isActive) {
    return GestureDetector(
      onTap: _switchAuthMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.black : Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 3,
            width: isActive ? 30 : 0,
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(2),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, bool isOptional = false, bool isConfirm = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      validator: (value) {
        if (isOptional) return null;
        if (value == null || value.isEmpty) return '$label cannot be empty';
        if (label == 'Email' && !value.contains('@')) return 'Please enter a valid email';
        if (label == 'Password' && value.length < 6) return 'Password must be at least 6 characters';
        if (isConfirm && value != _passwordController.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    );
  }

  Widget _buildSocialLogin() {
    return Column(
      children: [
        const SizedBox(height: 32),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12.0), child: Text('Or continue with', style: TextStyle(color: Colors.grey))),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialButton('assets/google.png', _signInWithGoogle),
            const SizedBox(width: 20),
            _buildSocialButton('assets/apple.png', () { _showErrorDialog("Login with Apple has not been implemented."); }),
          ],
        ),
      ],
    );
  }

  Widget _buildSocialButton(String assetPath, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Image.asset(assetPath, height: 24, width: 24, errorBuilder: (c,e,s) => Icon(assetPath.contains('google') ? Icons.android : Icons.apple, color: Colors.grey)),
        ],
      ),
    );
  }
}
