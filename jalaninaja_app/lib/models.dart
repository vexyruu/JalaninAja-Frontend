import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Represents a user from the leaderboard or a report author.
class User {
  final String name;
  final int points;
  final String? avatarUrl;

  User({
    required this.name,
    required this.points,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      name: json['name'] ?? 'Anonymous',
      points: json['points'] ?? 0,
      avatarUrl: json['avatar_url'],
    );
  }
}

/// Represents a full user profile with more details.
class UserProfile {
  final String userName;
  final String userEmail;
  final String? userAvatarUrl;
  final String userLevel;
  final int userPoints;
  final int reportsMade;
  final List<String> badges;

  UserProfile({
    required this.userName,
    required this.userEmail,
    this.userAvatarUrl,
    required this.userLevel,
    required this.userPoints,
    required this.reportsMade,
    required this.badges,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userName: json['user_name'] ?? 'N/A',
      userEmail: json['user_email'] ?? 'N/A',
      userAvatarUrl: json['user_avatar_url'],
      userLevel: json['user_level'] ?? 'Pejalan Kaki',
      userPoints: json['user_points'] ?? 0,
      reportsMade: json['reports_made'] ?? 0,
      badges: List<String>.from(json['badges'] ?? []),
    );
  }
}


/// Represents a community report.
class Report {
  final int reportId;
  final String? description;
  final String? photoUrl;
  final double latitude;
  final double longitude;
  final String category;
  final String? address;
  int upvoteCount;
  final DateTime createdAt;
  final User? author;
  bool isUpvoted;

  Report({
    required this.reportId,
    this.description,
    this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.category,
    this.address,
    required this.upvoteCount,
    required this.createdAt,
    this.author,
    this.isUpvoted = false,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      reportId: json['report_id'],
      description: json['description'],
      photoUrl: json['photo_url'],
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] ?? 'Uncategorized',
      address: json['address'],
      upvoteCount: json['upvote_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      author: json['Users'] != null ? User.fromJson(json['Users']) : null,
      isUpvoted: json['user_vote_status'] == 'up',
    );
  }
}

/// Represents a Google Places Autocomplete prediction.
class PlaceAutocomplete {
  final String description;
  final String mainText;
  final String secondaryText;

  PlaceAutocomplete({required this.description, required this.mainText, required this.secondaryText});

  factory PlaceAutocomplete.fromJson(Map<String, dynamic> json) {
    return PlaceAutocomplete(
      description: json['description'],
      mainText: json['structured_formatting']['main_text'],
      secondaryText: json['structured_formatting']['secondary_text'] ?? '',
    );
  }
}


/// Represents a point analyzed for walkability.
class AnalyzedPoint {
  final double latitude;
  final double longitude;
  double walkabilityScore; // Made mutable
  final List<String> detectedLabels;
  final String? photoUrl;
  final bool isResidential;
  final int treeCount; // Added field
  final double sidewalkArea; // Added field


  AnalyzedPoint({
    required this.latitude,
    required this.longitude,
    required this.walkabilityScore,
    required this.detectedLabels,
    this.photoUrl,
    required this.isResidential,
    required this.treeCount,
    required this.sidewalkArea,
  });
  
  LatLng toLatLng() => LatLng(latitude, longitude);

  factory AnalyzedPoint.fromJson(Map<String, dynamic> json) {
    return AnalyzedPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      walkabilityScore: (json['walkability_score'] as num? ?? 0.0).toDouble(),
      detectedLabels: List<String>.from(json['detected_labels'] ?? []),
      photoUrl: json['photo_url'],
      isResidential: json['is_residential_road'] ?? false,
      treeCount: json['tree_count'] ?? 0,
      sidewalkArea: (json['sidewalk_area'] as num? ?? 0.0).toDouble(),
    );
  }
}

/// Represents a single route alternative with its walkability score.
class RouteAlternative {
  double averageWalkabilityScore; // Made mutable
  final String overviewPolyline;
  final List<AnalyzedPoint> pointsAnalyzed;

  RouteAlternative({
    required this.averageWalkabilityScore,
    required this.overviewPolyline,
    required this.pointsAnalyzed,
  });

  factory RouteAlternative.fromJson(Map<String, dynamic> json) {
    var points = (json['points_analyzed'] as List)
          .map((pointJson) => AnalyzedPoint.fromJson(pointJson))
          .toList();

    return RouteAlternative(
      averageWalkabilityScore: (json['average_walkability_score'] as num).toDouble(),
      overviewPolyline: json['overview_polyline'],
      pointsAnalyzed: points,
    );
  }
}

/// Represents the status response for a route calculation job.
class RouteStatusResponse {
  final String status;
  List<RouteAlternative>? data;
  final String? error;

  RouteStatusResponse({required this.status, this.data, this.error});

  factory RouteStatusResponse.fromJson(Map<String, dynamic> json) {
    return RouteStatusResponse(
      status: json['status'],
      data: json['data'] != null
          ? (json['data'] as List).map((routeJson) => RouteAlternative.fromJson(routeJson)).toList()
          : null,
      error: json['error'],
    );
  }
}
