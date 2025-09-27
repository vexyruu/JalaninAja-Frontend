import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Service to fetch and hold environment/remote configuration.
/// Must be initialized on app startup.
class ConfigService {
  ConfigService._privateConstructor();
  static final ConfigService instance = ConfigService._privateConstructor();

  late final String apiBaseUrl;
  late final String supabaseUrl;
  late final String supabaseAnonKey;
  late final String googleMapsApiKey;
  late final String googleWebClientId;
  late final String googleIosClientId;

  Future<void> initialize() async {
    try {
      apiBaseUrl = dotenv.env['API_BASE_URL']!;
      if (apiBaseUrl.isEmpty) {
        throw Exception("API_BASE_URL is not defined in the .env file.");
      }

      final response = await http.get(Uri.parse('$apiBaseUrl/config'));
      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        supabaseUrl = config['supabase_url'];
        supabaseAnonKey = config['supabase_anon_key'];
        googleMapsApiKey = config['google_maps_api_key'];
        
        // These are still loaded from .env as they are client-specific
        googleWebClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
        googleIosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '';

        if (kDebugMode) {
          print('✅ Configuration successfully loaded from the server.');
        }
      } else {
        throw Exception('Failed to load config from server: Status code ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔴 FATAL ERROR: Could not load configuration. Ensure the API server is running and .env is correct. Error: $e');
      rethrow;
    }
  }
}

