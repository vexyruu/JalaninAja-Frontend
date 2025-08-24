
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

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

      final response = await http.get(Uri.parse('$apiBaseUrl/config'));
      if (response.statusCode == 200) {
        final config = json.decode(response.body);
        supabaseUrl = config['supabase_url'];
        supabaseAnonKey = config['supabase_anon_key'];
        googleMapsApiKey = config['google_maps_api_key'];
        print('✅ Configuration successfully loaded.');
      } else {
        throw Exception('Failed to load config from server: Status code ${response.statusCode}');
      }
    } catch (e) {
      print('🔴 FATAL ERROR: Could not load configuration. Error: $e');
      rethrow;
    }
  }
}