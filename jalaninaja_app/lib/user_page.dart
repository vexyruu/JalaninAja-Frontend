import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_screen.dart';
import 'config_service.dart';
import 'settings_page.dart';

class UserProfileData {
  final Map<String, dynamic> profile;
  final List<dynamic> topReports;

  UserProfileData({required this.profile, required this.topReports});
}

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final String _apiBaseUrl = ConfigService.instance.apiBaseUrl;
  late Future<UserProfileData> _profileDataFuture;

  @override
  void initState() {
    super.initState();
    _profileDataFuture = _fetchCombinedData();
  }

  // --- NEW: Helper to get the auth token ---
  String? _getAuthToken() {
    return Supabase.instance.client.auth.currentSession?.accessToken;
  }

  Future<UserProfileData> _fetchCombinedData() async {
    final token = _getAuthToken();
    if (token == null) {
      throw Exception('You must be logged in to view your profile.');
    }
    
    try {
      // Use Future.wait to fetch both pieces of data concurrently
      final results = await Future.wait([
        _fetchUserProfile(token),
        _fetchUserTopReports(token),
      ]);
      
      final profile = results[0] as Map<String, dynamic>;
      final topReports = results[1] as List<dynamic>;

      return UserProfileData(
        profile: profile,
        topReports: topReports,
      );
    } catch (e) {
      debugPrint('Error fetching combined profile data: $e');
      throw Exception('Failed to load profile data.');
    }
  }

  // --- UPDATED: Fetches from /users/me using a token ---
  Future<Map<String, dynamic>> _fetchUserProfile(String token) async {
    final response = await http.get(
      Uri.parse("$_apiBaseUrl/users/me"),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load user profile. Status: ${response.statusCode}');
    }
  }

  // --- UPDATED: Fetches from /reports/me/top using a token ---
  Future<List<dynamic>> _fetchUserTopReports(String token) async {
    final response = await http.get(
      Uri.parse("$_apiBaseUrl/reports/me/top"),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load top reports. Status: ${response.statusCode}');
    }
  }
  
  void _navigateToSettings() async {
    // Navigate to settings and wait for it to pop.
    // If it returns, refresh the profile data.
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
    setState(() {
      _profileDataFuture = _fetchCombinedData();
    });
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Yes, Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
            onPressed: _navigateToSettings,
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
            onPressed: _showLogoutConfirmation,
            tooltip: 'Log Out',
          ),
        ],
      ),
      body: FutureBuilder<UserProfileData>(
        future: _profileDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('${snapshot.error}'));
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No profile data found.'));
          }

          final profileData = snapshot.data!;
          final profile = profileData.profile;
          final topReports = profileData.topReports;
          final avatarUrl = profile['user_avatar_url'];
          final userLevel = profile['user_level'];

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _profileDataFuture = _fetchCombinedData();
              });
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              children: <Widget>[
                const SizedBox(height: 20),
                _buildProfileHeader(profile['user_name'], profile['user_email'], avatarUrl, textTheme),
                const SizedBox(height: 24),
                _buildStatsRow(profile['reports_made'], profile['user_points'], textTheme),
                const SizedBox(height: 32),
                if (userLevel != 'Pejalan Kaki') ...[
                  Text('Badge', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildBadgeCard(userLevel, textTheme),
                  const SizedBox(height: 32),
                ],
                Text('Top Reports', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildTopReportsList(topReports, profile['user_name'], avatarUrl, textTheme),
                const SizedBox(height: 48),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(String name, String email, String? avatarUrl, TextTheme textTheme) {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.grey.shade300,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? const Icon(Icons.person, size: 30, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(email, style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow(int contributions, int points, TextTheme textTheme) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('$contributions', 'Contribution', textTheme)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(points.toString(), 'Point', textTheme)),
      ],
    );
  }

  Widget _buildStatCard(String value, String label, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(value, style: textTheme.titleLarge?.copyWith(color: const Color(0xFF2E7D32))),
          const SizedBox(height: 4),
          Text(label, style: textTheme.bodyMedium?.copyWith(color: const Color(0xFF2E7D32))),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(String badgeName, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: Colors.green.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFC107),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(badgeName, style: textTheme.titleSmall),
                Text('You have achieved ${badgeName.toLowerCase()}', style: textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopReportsList(List<dynamic> reports, String userName, String? avatarUrl, TextTheme textTheme) {
    if (reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: Text('You have no top reports yet.', style: textTheme.bodyMedium)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        return _buildReportCard(report, userName, avatarUrl, textTheme);
      },
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report, String userName, String? avatarUrl, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade300,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Text(userName, style: textTheme.titleSmall),
                const Spacer(),
                const Icon(Icons.star, color: Color(0xFFFFC107), size: 18),
              ],
            ),
          ),
          if (report['photo_url'] != null)
            Image.network(
              report['photo_url'],
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const SizedBox(height: 150, child: Icon(Icons.broken_image, color: Colors.grey)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(report['description'] ?? 'No description', style: textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        report['address'] ?? 'Address not available',
                        style: textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.thumb_up, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text((report['upvote_count'] ?? 0).toString()),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

