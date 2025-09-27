import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api_service.dart';
import 'auth_screen.dart';
import 'models.dart' as app_models;
import 'settings_page.dart';
import 'report_detail_page.dart';
import 'widgets/report_card.dart';

class UserProfilePageData {
  final app_models.UserProfile profile;
  final List<app_models.Report> topReports;

  UserProfilePageData({required this.profile, required this.topReports});
}

class UserPage extends StatefulWidget {
  const UserPage({super.key});

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  late Future<UserProfilePageData> _profileDataFuture;

  @override
  void initState() {
    super.initState();
    _profileDataFuture = _fetchCombinedData();
  }

  Future<UserProfilePageData> _fetchCombinedData() async {
    try {
      final results = await Future.wait([
        ApiService.instance.getUserProfile(),
        ApiService.instance.getMyTopReports(),
      ]);
      
      final profile = results[0] as app_models.UserProfile;
      final topReports = results[1] as List<app_models.Report>;

      return UserProfilePageData(
        profile: profile,
        topReports: topReports,
      );
    } catch (e) {
      debugPrint('Error fetching combined profile data: $e');
      rethrow;
    }
  }
  
  void _navigateToSettings() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const SettingsPage()),
    );
    if (result == true) {
      _refreshData();
    }
  }

  void _refreshData() {
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      body: FutureBuilder<UserProfilePageData>(
        future: _profileDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Failed to load profile data.\nPlease try again.\n\nError: ${snapshot.error}', textAlign: TextAlign.center),
              )
            );
          } else if (!snapshot.hasData) {
            return const Center(child: Text('No profile data found.'));
          }

          final profile = snapshot.data!.profile;
          final topReports = snapshot.data!.topReports;

          return RefreshIndicator(
            onRefresh: () async => _refreshData(),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              children: <Widget>[
                const SizedBox(height: 20),
                _buildProfileHeader(profile, textTheme),
                const SizedBox(height: 24),
                _buildStatsRow(profile, textTheme),
                const SizedBox(height: 32),
                if (profile.badges.isNotEmpty) ...[
                  Text('Badges', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildBadgeCard(profile.userLevel, textTheme),
                  const SizedBox(height: 32),
                ],
                Text('Top Reports', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildTopReportsList(topReports, profile, textTheme),
                const SizedBox(height: 48),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(app_models.UserProfile profile, TextTheme textTheme) {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: Colors.grey.shade300,
          backgroundImage: profile.userAvatarUrl != null ? NetworkImage(profile.userAvatarUrl!) : null,
          child: profile.userAvatarUrl == null
              ? Text(profile.userName.isNotEmpty ? profile.userName[0].toUpperCase() : '?', style: textTheme.headlineSmall?.copyWith(color: Colors.white))
              : null,
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profile.userName, style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(profile.userEmail, style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow(app_models.UserProfile profile, TextTheme textTheme) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('${profile.reportsMade}', 'Reports', textTheme)),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(profile.userPoints.toString(), 'Points', textTheme)),
      ],
    );
  }

  Widget _buildStatCard(String value, String label, TextTheme textTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 1.5),
      ),
      child: Column(
        children: [
          Text(value, style: textTheme.titleLarge?.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: textTheme.bodyMedium?.copyWith(color: const Color(0xFF2E7D32))),
        ],
      ),
    );
  }

  Widget _buildBadgeCard(String badgeName, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(badgeName, style: textTheme.titleSmall),
                  Text('You have achieved this milestone!', style: textTheme.bodySmall, maxLines: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopReportsList(List<app_models.Report> reports, app_models.UserProfile currentUser, TextTheme textTheme) {
    if (reports.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(
            child: Text(
          'Your most upvoted reports will appear here.',
          style: textTheme.bodyMedium?.copyWith(color: Colors.grey),
          textAlign: TextAlign.center,
        )),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: reports.length,
      itemBuilder: (context, index) {
        final report = reports[index];
        return _buildReportCard(report, currentUser, textTheme);
      },
    );
  }

  Widget _buildReportCard(app_models.Report report, app_models.UserProfile author, TextTheme textTheme) {
    final reportWithAuthor = app_models.Report(
      reportId: report.reportId,
      description: report.description,
      photoUrl: report.photoUrl,
      latitude: report.latitude,
      longitude: report.longitude,
      category: report.category,
      address: report.address,
      upvoteCount: report.upvoteCount,
      createdAt: report.createdAt,
      author: app_models.User(name: author.userName, points: author.userPoints, avatarUrl: author.userAvatarUrl),
    );

    return ReportCard(
      report: reportWithAuthor,
      isTopReport: true,
      showVoteButton: false, 
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ReportDetailPage(initialReport: reportWithAuthor),
          ),
        );
      },
      onUpvote: () {},
    );
  }
}
