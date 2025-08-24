import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_report_page.dart';
import 'config_service.dart';

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Community'),
          automaticallyImplyLeading: false,
          bottom: TabBar(
            labelStyle: Theme.of(context).textTheme.titleSmall,
            tabs: const [
              Tab(text: 'Community Reports'),
              Tab(text: 'Leaderboard'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            CommunityReportsTab(apiBaseUrl: ConfigService.instance.apiBaseUrl),
            LeaderboardTab(apiBaseUrl: ConfigService.instance.apiBaseUrl),
          ],
        ),
      ),
    );
  }
}

// TAB 1: COMMUNITY REPORTS
class CommunityReportsTab extends StatefulWidget {
  final String apiBaseUrl;
  const CommunityReportsTab({super.key, required this.apiBaseUrl});

  @override
  State<CommunityReportsTab> createState() => _CommunityReportsTabState();
}

class _CommunityReportsTabState extends State<CommunityReportsTab> {
  final ScrollController _scrollController = ScrollController();
  int _page = 0;
  bool _isLoadingMore = false;
  List<dynamic> _reports = [];

  @override
  void initState() {
    super.initState();
    _fetchReports(0);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent && !_isLoadingMore) {
      _page++;
      _fetchReports(_page);
    }
  }

  Future<void> _fetchReports(int page) async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });
    const int limit = 10;
    final offset = page * limit;
    try {
      final response = await http.get(Uri.parse('${widget.apiBaseUrl}/reports?offset=$offset&limit=$limit'));
      if (response.statusCode == 200) {
        final newReports = json.decode(response.body) as List;
        setState(() {
          if (page == 0) {
            _reports = newReports;
          } else {
            _reports.addAll(newReports);
          }
        });
      } else {
        throw Exception('Failed to load reports');
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to the server.')),
        );
      }
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refreshReports() async {
    _page = 0;
    await _fetchReports(0);
  }

  Future<void> _upvoteReport(int reportId) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You must be logged in to upvote.')));
      return;
    }

    final reportIndex = _reports.indexWhere((report) => report['report_id'] == reportId);
    if (reportIndex == -1) return;

    final originalUpvoteCount = _reports[reportIndex]['upvote_count'];

    setState(() {
      _reports[reportIndex]['upvote_count'] = originalUpvoteCount + 1;
    });

    try {
      final response = await http.post(
        Uri.parse('${widget.apiBaseUrl}/reports/$reportId/upvote'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      
      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _reports[reportIndex]['upvote_count'] = originalUpvoteCount;
        });
        final error = json.decode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${error['detail']}')));
      } else {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upvote successful!')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reports[reportIndex]['upvote_count'] = originalUpvoteCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('An error occurred: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _refreshReports,
        child: _reports.isEmpty && !_isLoadingMore
            ? const Center(child: Text('No reports yet. Be the first to post!'))
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _reports.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _reports.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final report = _reports[index];
                  return _buildReportCard(report, context);
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CreateReportPage()),
          );
          if (result == true && mounted) {
            _refreshReports();
          }
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
      ),
    );
  }

  String _getUserLevel(int points) {
    if (points >= 1500) return "Legenda Gotong Royong";
    if (points >= 750) return "Jawara Jalan";
    if (points >= 300) return "Pelopor Trotoar";
    if (points >= 100) return "Penjelajah Kota";
    return "Pejalan Kaki";
  }

  Widget _buildReportCard(Map<String, dynamic> report, BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final userName = report['Users']?['name'] ?? 'Anonymous';
    final userPoints = report['Users']?['points'] ?? 0;
    final avatarUrl = report['Users']?['avatar_url'];
    final category = report['category'] ?? 'No Category';
    final userLevel = _getUserLevel(userPoints);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? const Icon(Icons.person, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName, style: textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '$userLevel - $userPoints Points',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (userPoints >= 100)
                  const Icon(Icons.verified, color: Colors.amber, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            if (report['photo_url'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  report['photo_url'],
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) => Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(category, style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(report['description'] ?? 'No description provided', style: textTheme.bodyMedium),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    report['address'] ?? 'Address not available',
                    style: textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _upvoteReport(report['report_id']),
                  icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
                  label: Text((report['upvote_count'] ?? 0).toString()),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.grey.shade300)
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

//  TAB 2: LEADERBOARD
class LeaderboardTab extends StatefulWidget {
  final String apiBaseUrl;
  const LeaderboardTab({super.key, required this.apiBaseUrl});

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  late Future<List<dynamic>> _leaderboardFuture;

  @override
  void initState() {
    super.initState();
    _leaderboardFuture = _fetchLeaderboard();
  }

  Future<List<dynamic>> _fetchLeaderboard() async {
    try {
      final response = await http.get(Uri.parse('${widget.apiBaseUrl}/leaderboard'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load leaderboard');
      }
    } catch (e) {
      debugPrint('Error fetching leaderboard: $e');
      throw Exception('Could not connect to the server.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FutureBuilder<List<dynamic>>(
        future: _leaderboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('The leaderboard is empty.'));
          }

          final leaderboard = snapshot.data!;
          return RefreshIndicator(
             onRefresh: () async {
                setState(() {
                  _leaderboardFuture = _fetchLeaderboard();
                });
              },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: leaderboard.length,
              itemBuilder: (context, index) {
                final user = leaderboard[index];
                return _buildLeaderboardCard(user, index + 1, context);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeaderboardCard(Map<String, dynamic> user, int rank, BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final avatarUrl = user['avatar_url'];
    final points = user['points'] ?? 0;
    
    final Map<int, Color> rankColors = {
      1: const Color(0xFFFFD700), // Gold
      2: const Color(0xFFC0C0C0), // Silver
      3: const Color(0xFFCD7F32), // Bronze
    };
    final rankColor = rankColors[rank];

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: rankColor ?? Colors.grey.shade300)
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: rankColor?.withOpacity(0.2) ?? Colors.grey[200],
              child: Text('$rank', style: textTheme.titleSmall?.copyWith(color: rankColor ?? textTheme.titleSmall?.color)),
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user['name'] ?? 'Anonymous', style: textTheme.titleSmall),
                  Text('$points points', style: textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (rankColor != null)
              Icon(Icons.emoji_events, color: rankColor),
          ],
        ),
      ),
    );
  }
}