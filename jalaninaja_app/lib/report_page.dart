import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'widgets/report_card.dart';
import 'api_service.dart';
import 'create_report_page.dart';
import 'models.dart' as app_models;
import 'report_detail_page.dart';

enum LeaderboardPeriod { week, month, year }

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Image.asset('assets/JalaninAjaLogoNoBG.png', height: 24),
          centerTitle: true,
          automaticallyImplyLeading: false,
          bottom: TabBar(
            labelStyle: Theme.of(context).textTheme.titleSmall,
            tabs: const [
              Tab(text: 'Community Reports'),
              Tab(text: 'Leaderboard'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CommunityReportsTab(),
            LeaderboardTab(),
          ],
        ),
      ),
    );
  }
}

// TAB 1: COMMUNITY REPORTS
class CommunityReportsTab extends StatefulWidget {
  const CommunityReportsTab({super.key});

  @override
  State<CommunityReportsTab> createState() => _CommunityReportsTabState();
}

class _CommunityReportsTabState extends State<CommunityReportsTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  int _page = 0;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isVoting = false;
  List<app_models.Report> _reports = [];

  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchInitialReports();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isSearching) return;

    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading && _hasMore) {
      _fetchMoreReports();
    }
  }

  Future<void> _fetchInitialReports() async {
    setState(() {
      _page = 0;
      _isLoading = true;
      _hasMore = true;
      _isSearching = false;
    });
    try {
      final newReports = await ApiService.instance.getReports(page: 0);
      setState(() {
        _reports = newReports;
        if (newReports.length < 10) _hasMore = false;
      });
    } catch (e) {
      _showErrorSnackBar('Could not fetch reports: $e');
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreReports() async {
    setState(() => _isLoading = true);
    _page++;
    try {
      final newReports = await ApiService.instance.getReports(page: _page);
      setState(() {
        _reports.addAll(newReports);
        if (newReports.length < 10) _hasMore = false;
      });
    } catch (e) {
      _showErrorSnackBar('Could not fetch more reports: $e');
      _page--;
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _isSearching = true;
      _hasMore = false;
    });
    try {
      final searchResults = await ApiService.instance.searchReportsByLocation(query);
      setState(() {
        _reports = searchResults;
      });
    } catch (e) {
      _showErrorSnackBar('Search failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    _fetchInitialReports();
  }
  
  Future<void> _handleRefresh() async {
    _searchController.clear();
    await _fetchInitialReports();
  }

  Future<void> _vote(int reportId, Future<void> Function(int) apiCall) async {
    if (_isVoting) return;
    setState(() => _isVoting = true);

    try {
      await apiCall(reportId);
      _showSuccessSnackBar('Vote registered!');
      _handleRefresh(); 
    } catch (e) {
      _showErrorSnackBar('Vote failed: $e');
    } finally {
      if(mounted) setState(() => _isVoting = false);
    }
  }

  void _navigateToDetail(app_models.Report report) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReportDetailPage(initialReport: report),
      ),
    );
    if (result == true) {
      _handleRefresh();
    }
  }
  
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }
  
  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: (_reports.isEmpty && !_isLoading)
                  ? Center(child: Text(_isSearching ? 'No reports found for "$_searchQuery".' : 'No reports yet. Be the first to post!'))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _reports.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _reports.length) {
                          return _hasMore && !_isSearching
                            ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                            : (_isSearching ? const SizedBox.shrink() : const Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text("You've reached the end."))));
                        }
                        final report = _reports[index];
                        return ReportCard(
                          report: report,
                          onTap: () => _navigateToDetail(report),
                          onUpvote: () => _vote(report.reportId, ApiService.instance.upvoteReport),
                          // FIX: Removed the onDownvote parameter as it no longer exists
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CreateReportPage()),
          );
          if (result == true && mounted) {
            _fetchInitialReports();
          }
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TypeAheadField<app_models.PlaceAutocomplete>(
        controller: _searchController,
        suggestionsCallback: (pattern) async {
          if (pattern.trim().isEmpty) return [];
          return await ApiService.instance.autocompleteAddress(pattern);
        },
        itemBuilder: (context, suggestion) {
          return ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(suggestion.mainText),
            subtitle: Text(suggestion.secondaryText),
          );
        },
        onSelected: (suggestion) {
          _searchController.text = suggestion.description;
          _performSearch(suggestion.description);
        },
        builder: (context, controller, focusNode) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onSubmitted: (value) {
              _performSearch(value);
            },
            decoration: InputDecoration(
              hintText: 'Search by location (e.g., "Surabaya")',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _clearSearch(),
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30.0),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30.0),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          );
        },
        emptyBuilder: (context) => const Padding(
          padding: EdgeInsets.all(12.0),
          child: Text('No matching locations found.'),
        ),
      ),
    );
  }
}

class LeaderboardTab extends StatefulWidget {
  const LeaderboardTab({super.key});

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> {
  LeaderboardPeriod _selectedPeriod = LeaderboardPeriod.week;
  late Future<List<app_models.User>> _leaderboardFuture;
  
  final Map<LeaderboardPeriod, String> _periodApiMap = {
    LeaderboardPeriod.week: 'week',
    LeaderboardPeriod.month: 'month',
    LeaderboardPeriod.year: 'year',
  };

  @override
  void initState() {
    super.initState();
    _fetchLeaderboard();
  }
  
  void _fetchLeaderboard() {
    setState(() {
      _leaderboardFuture = ApiService.instance.getLeaderboard(
        period: _periodApiMap[_selectedPeriod]!,
      );
    });
  }

  Widget _buildPeriodSelector() {
    final Map<LeaderboardPeriod, String> periodLabels = {
      LeaderboardPeriod.week: 'This Week',
      LeaderboardPeriod.month: 'This Month',
      LeaderboardPeriod.year: 'This Year',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: periodLabels.keys.map((period) {
          final isSelected = _selectedPeriod == period;
          return ChoiceChip(
            label: Text(periodLabels[period]!),
            selected: isSelected,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedPeriod = period;
                  _fetchLeaderboard();
                });
              }
            },
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildPeriodSelector(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _fetchLeaderboard(),
              child: FutureBuilder<List<app_models.User>>(
                future: _leaderboardFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('The leaderboard for this period is empty.'));
                  }

                  final leaderboard = snapshot.data!;
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: leaderboard.length,
                    itemBuilder: (context, index) {
                      final user = leaderboard[index];
                      return _buildLeaderboardCard(user, index + 1, context);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardCard(app_models.User user, int rank, BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    
    final Map<int, Color> rankColors = {
      1: const Color(0xFFFFD700), // Gold
      2: const Color(0xFFC0C0C0), // Silver
      3: const Color(0xFFCD7F32), // Bronze
    };
    final rankColor = rankColors[rank];

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: rankColor ?? Colors.transparent, width: 1.5)
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
              backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null
                  ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?', style: textTheme.titleLarge?.copyWith(color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: textTheme.titleSmall),
                  Text('${user.points} points', style: textTheme.bodySmall),
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

