import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models.dart' as app_models;

class ReportCard extends StatelessWidget {
  final app_models.Report report;
  // ROLLED BACK: Simplified callbacks
  final VoidCallback onUpvote;
  final bool isTopReport;
  final VoidCallback? onTap;
  final bool showVoteButton; // Renamed for clarity

  const ReportCard({
    super.key,
    required this.report,
    required this.onUpvote,
    this.isTopReport = false,
    this.onTap,
    this.showVoteButton = true, // Default to true
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final timeAgo = timeago.format(report.createdAt.toLocal());
    final author = report.author;

    return Card(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.08),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: author?.avatarUrl != null ? NetworkImage(author!.avatarUrl!) : null,
                    child: author?.avatarUrl == null ? const Icon(Icons.person, color: Colors.grey) : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author?.name ?? 'Anonymous', style: textTheme.titleSmall),
                        if (author != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.military_tech_outlined, color: Colors.amber[800], size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '${author.points} Points',
                                style: textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(timeAgo, style: textTheme.bodySmall),
                ],
              ),
            ),
            
            if (report.photoUrl != null)
              Container(
                height: 200,
                width: double.infinity,
                color: Colors.grey.shade100,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      report.photoUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          report.category,
                          style: textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (isTopReport)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFC107),
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.star, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Top Report',
                                style: textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (report.description != null && report.description!.isNotEmpty) ...[
                    Text(report.description!, style: textTheme.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, color: Colors.grey[600], size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          report.address ?? 'Address not available',
                          style: textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // ROLLED BACK: Simplified vote button section
            if (showVoteButton) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onUpvote,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.thumb_up_alt_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Upvote (${report.upvoteCount})',
                            style: textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

