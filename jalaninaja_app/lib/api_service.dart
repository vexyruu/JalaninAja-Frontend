import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart' as app_models;
import 'config_service.dart';

/// A singleton service class for handling all network requests to the backend API.
class ApiService {
  ApiService._privateConstructor();
  static final ApiService instance = ApiService._privateConstructor();

  final String _apiBaseUrl = ConfigService.instance.apiBaseUrl;

  // Private helper to get authorization headers. Throws if not authenticated.
  Map<String, String> _getAuthHeaders() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw Exception("User is not authenticated. Please log in.");
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Helper to handle API responses and errors.
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return json.decode(response.body);
    } else {
      final decodedBody = json.decode(response.body);
      throw Exception(decodedBody['detail'] ?? 'An API error occurred.');
    }
  }

  // --- User & Profile ---
  Future<app_models.UserProfile> getUserProfile() async {
    final response = await http.get(
      Uri.parse("$_apiBaseUrl/users/me"),
      headers: _getAuthHeaders(),
    );
    final data = _handleResponse(response);
    return app_models.UserProfile.fromJson(data);
  }

  Future<void> updateUserProfile({required String name, String? avatarUrl}) async {
    final Map<String, dynamic> body = {'name': name};
    if (avatarUrl != null) {
      body['avatar_url'] = avatarUrl;
    }

    final response = await http.patch(
      Uri.parse('$_apiBaseUrl/users/me'),
      headers: _getAuthHeaders(),
      body: json.encode(body),
    );
    _handleResponse(response);
  }

  Future<List<app_models.Report>> getMyTopReports() async {
    final response = await http.get(
      Uri.parse("$_apiBaseUrl/reports/me/top"),
      headers: _getAuthHeaders(),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => app_models.Report.fromJson(json)).toList();
  }
  
  // --- Reports & Community ---
  Future<List<app_models.Report>> getReports({int page = 0, int limit = 10}) async {
    final offset = page * limit;
    final response = await http.get(
        Uri.parse('$_apiBaseUrl/reports?offset=$offset&limit=$limit'),
        headers: _getAuthHeaders(),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => app_models.Report.fromJson(json)).toList();
  }

  Future<app_models.Report> getReportDetails(int reportId) async {
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/reports/$reportId'),
      headers: _getAuthHeaders(),
    );
    final data = _handleResponse(response);
    return app_models.Report.fromJson(data);
  }

  // FIX: Added authentication headers to the search request.
  Future<List<app_models.Report>> searchReportsByLocation(String query) async {
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/reports/search?query=${Uri.encodeComponent(query)}'),
      headers: _getAuthHeaders(),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => app_models.Report.fromJson(json)).toList();
  }

  Future<List<app_models.Report>> getNearbyReports(double lat, double lng) async {
    final response = await http.get(
        Uri.parse('$_apiBaseUrl/reports/nearby?lat=$lat&lng=$lng'),
        headers: _getAuthHeaders(),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => app_models.Report.fromJson(json)).toList();
  }

  Future<List<app_models.User>> getLeaderboard({String period = 'week'}) async {
    final response = await http.get(
        Uri.parse('$_apiBaseUrl/leaderboard?period=$period'),
        headers: _getAuthHeaders(),
    );
    final List<dynamic> data = _handleResponse(response);
    return data.map((json) => app_models.User.fromJson(json)).toList();
  }

  Future<void> upvoteReport(int reportId) async {
     final response = await http.post(
      Uri.parse('$_apiBaseUrl/reports/$reportId/upvote'),
      headers: _getAuthHeaders(),
    );
    _handleResponse(response);
  }
  
  Future<void> removeVote(int reportId) async {
    final response = await http.delete(
      Uri.parse('$_apiBaseUrl/reports/$reportId/vote'),
      headers: _getAuthHeaders(),
    );
    _handleResponse(response);
  }
  
  Future<void> createReport({
    required String category,
    String? description,
    required double latitude,
    required double longitude,
    XFile? imageFile,
  }) async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) throw Exception("Not authenticated");

    final request = http.MultipartRequest('POST', Uri.parse("$_apiBaseUrl/reports"));
    request.headers['Authorization'] = 'Bearer $token';
    
    request.fields['category'] = category;
    request.fields['latitude'] = latitude.toString();
    request.fields['longitude'] = longitude.toString();
    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }

    if (imageFile != null) {
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    _handleResponse(response);
  }

  // --- Maps & Routes ---
  Future<String> calculateRoute({
    required String origin,
    required String destination,
    required String mode,
  }) async {
    final response = await http.post(
      Uri.parse("$_apiBaseUrl/calculate-routes"),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'origin_address': origin,
        'destination_address': destination,
        'mode': mode,
      }),
    );
    final data = _handleResponse(response);
    return data['job_id'];
  }

  Future<app_models.RouteStatusResponse> pollRouteStatus(String jobId) async {
    final response = await http.get(Uri.parse("$_apiBaseUrl/routes/status/$jobId"));
    final data = _handleResponse(response);
    return app_models.RouteStatusResponse.fromJson(data);
  }

  Future<List<app_models.PlaceAutocomplete>> autocompleteAddress(String query, {double? lat, double? lng}) async {
    final Map<String, String> queryParameters = {'query': query};
    if (lat != null && lng != null) {
      queryParameters['lat'] = lat.toString();
      queryParameters['lng'] = lng.toString();
    }
    
    final uri = Uri.parse("$_apiBaseUrl/autocomplete-address").replace(queryParameters: queryParameters);
    
    final response = await http.get(uri);
    final data = _handleResponse(response);
    final List<dynamic> predictions = data['predictions'];
    return predictions.map((json) => app_models.PlaceAutocomplete.fromJson(json)).toList();
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    final response = await http.get(Uri.parse('$_apiBaseUrl/reverse-geocode?lat=$lat&lng=$lng'));
    final data = _handleResponse(response);
    return data['address'] ?? 'Address not found';
  }
}

