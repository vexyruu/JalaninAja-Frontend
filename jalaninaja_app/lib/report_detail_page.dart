import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'api_service.dart';
import 'models.dart' as app_models;

class ReportDetailPage extends StatefulWidget {
  final app_models.Report initialReport;

  const ReportDetailPage({super.key, required this.initialReport});

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  // FIX: Refactored state management to remove FutureBuilder for more stability.
  app_models.Report? _report;
  bool _isLoading = true; // For initial load
  bool _isVoting = false; // To disable button during API call
  bool _didVoteOccur = false; // To notify previous page to refresh

  @override
  void initState() {
    super.initState();
    _report = widget.initialReport; // Show initial data immediately
    _fetchReportDetails(); // Fetch the latest details in the background
  }

  Future<void> _fetchReportDetails() async {
    if (!_isLoading) setState(() => _isLoading = true);
    
    try {
      final detailedReport = await ApiService.instance.getReportDetails(widget.initialReport.reportId);
      if (mounted) {
        setState(() {
          _report = detailedReport;
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to load report details: $e');
        // If the report is truly not found, pop the screen
        if (e.toString().toLowerCase().contains("not found")) {
          Navigator.of(context).pop();
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpvote() async {
    if (_isVoting || _report == null) return;
    setState(() {
      _isVoting = true;
      _didVoteOccur = true; // Mark that a voting action was attempted
    });

    try {
      if (_report!.isUpvoted) {
        await ApiService.instance.removeVote(_report!.reportId);
        _showSuccessSnackBar('Upvote removed');
      } else {
        await ApiService.instance.upvoteReport(_report!.reportId);
        _showSuccessSnackBar('Report upvoted!');
      }
      await _fetchReportDetails(); // Refresh data after voting
    } catch (e) {
      _showErrorSnackBar('Action failed: $e');
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.green));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop(_didVoteOccur);
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _report == null 
              ? _buildErrorView()
              : RefreshIndicator(
                  onRefresh: _fetchReportDetails,
                  child: _buildContent(_report!),
                ),
    );
  }

  Widget _buildErrorView() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              "Could not load report details.",
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "The report may have been deleted or there was a network issue.",
                style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildContent(app_models.Report report) {
    final textTheme = Theme.of(context).textTheme;
    final timeAgo = timeago.format(report.createdAt.toLocal());
    final author = report.author;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Author Info
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: author?.avatarUrl != null ? NetworkImage(author!.avatarUrl!) : null,
              child: author?.avatarUrl == null ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(author?.name ?? 'Anonymous', style: textTheme.titleMedium),
                  Text(timeAgo, style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Image
        if (report.photoUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              report.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                height: 200,
                color: Colors.grey[200],
                child: const Center(child: Icon(Icons.broken_image)),
              ),
            ),
          ),
        const SizedBox(height: 16),

        // Category and Vote Count
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(report.category, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(
              '${report.upvoteCount} Upvotes',
              style: textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
            ),
          ],
        ),
        const Divider(height: 32),

        // Description
        if (report.description != null && report.description!.isNotEmpty) ...[
          Text(report.description!, style: textTheme.bodyLarge?.copyWith(fontSize: 16)),
          const SizedBox(height: 24),
        ],

        // Vote Button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: Icon(
              report.isUpvoted ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
            ),
            label: Text(
              report.isUpvoted ? 'Upvoted' : 'Upvote',
              style: const TextStyle(fontSize: 16)
            ),
            onPressed: _isVoting ? null : _handleUpvote,
            style: FilledButton.styleFrom(
              backgroundColor: report.isUpvoted ? Colors.blue.shade700 : Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        const Divider(height: 32),

        // Location Info
        ListTile(
          leading: const Icon(Icons.location_on_outlined, color: Colors.grey),
          title: Text(report.address ?? 'Address not available'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(report.latitude, report.longitude),
                zoom: 16,
              ),
              markers: {
                Marker(
                  markerId: MarkerId(report.reportId.toString()),
                  position: LatLng(report.latitude, report.longitude),
                ),
              },
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
            ),
          ),
        ),
      ],
    );
  }
}

