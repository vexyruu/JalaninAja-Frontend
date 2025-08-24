import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
  
  bool _isLoading = false;
  String? _avatarUrl;
  XFile? _newAvatarFile; 

  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _getInitialProfile();
  }

  Future<Map<String, dynamic>> _getInitialProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception("User not logged in.");

      final response = await http.get(Uri.parse('${ConfigService.instance.apiBaseUrl}/users/$userId'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _usernameController.text = data['user_name'] ?? '';
        _emailController.text = data['user_email'] ?? '';
        _avatarUrl = data['user_avatar_url'];
        return data;
      } else {
        throw Exception("Failed to load profile.");
      }
    } catch (e) {
      _showErrorSnackBar(e.toString());
      rethrow;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final imageFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
    );
    if (imageFile != null) {
      setState(() {
        _newAvatarFile = imageFile;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      String? newAvatarUrl = _avatarUrl;
      if (_newAvatarFile != null) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw Exception('User not logged in');

        final bytes = await _newAvatarFile!.readAsBytes();
        final fileExt = _newAvatarFile!.path.split('.').last;
        final fileName = 'avatar.$fileExt';
        final filePath = '${user.id}/$fileName';

        await Supabase.instance.client.storage.from('avatars').uploadBinary(
              filePath,
              bytes,
              fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
            );
        newAvatarUrl = Supabase.instance.client.storage
            .from('avatars')
            .getPublicUrl(filePath);
      }

      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token == null) throw Exception("Not authenticated.");

      final response = await http.patch(
        Uri.parse('${ConfigService.instance.apiBaseUrl}/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'name': _usernameController.text.trim(),
          'avatar_url': newAvatarUrl,
        }),
      );

      if (response.statusCode == 200) {
        _showSuccessSnackBar('Profile updated successfully!');
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        final error = json.decode(response.body);
        throw Exception(error['detail'] ?? 'Failed to update profile.');
      }

    } on StorageException catch (e) {
      _showErrorSnackBar("Storage Error: ${e.message}");
    } catch (e) {
      _showErrorSnackBar('An error occurred: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPasswordController.text.isEmpty) {
      _showErrorSnackBar('New password cannot be empty.');
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showErrorSnackBar('Password must be at least 6 characters.');
      return;
    }

    Navigator.of(context).pop(); 
    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text.trim()),
      );
      _newPasswordController.clear();
      _showSuccessSnackBar('Password changed successfully!');
    } on AuthException catch (e) {
      _showErrorSnackBar(e.message);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void _showChangePasswordDialog() {
    _newPasswordController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Password'),
          content: TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New Password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _changePassword,
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Personal Data'),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildProfilePhotoCard(),
                      const SizedBox(height: 24),
                      _buildTextField(_usernameController, 'Username', Icons.person_outline),
                      const SizedBox(height: 16),
                      _buildTextField(_emailController, 'Email', Icons.email_outlined, enabled: false),
                      const SizedBox(height: 16),
                      _buildPasswordField(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _updateProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Update', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildProfilePhotoCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'My Personal Data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Details about my personal data',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade300,
                    // Display the new image file if it exists, otherwise show the existing URL.
                    backgroundImage: _newAvatarFile != null
                        ? FileImage(File(_newAvatarFile!.path))
                        : (_avatarUrl != null ? NetworkImage(_avatarUrl!) : null) as ImageProvider?,
                    child: _avatarUrl == null && _newAvatarFile == null
                        ? const Icon(Icons.person, size: 50, color: Colors.white)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Upload Photo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Format should be in .jpeg, .png atleast\n800x800px and less than 5MB',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool enabled = true}) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: enabled ? Colors.white : Colors.grey[200],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      validator: (value) {
        if (label == 'Username' && (value == null || value.isEmpty)) {
          return '$label cannot be empty';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.lock_outline),
        title: const Text('Change Password'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: _showChangePasswordDialog,
      ),
    );
  }
}
