import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'config_service.dart'; 

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  LatLng? _currentLocation;
  bool _isLoading = false;
  String _loadingMessage = 'Calculating...'; // NEW: More descriptive loading message
  bool _isSearchCardExpanded = false;
  String _selectedMode = "distance_walkability";

  List<Map<String, dynamic>> _routeAlternatives = [];
  int _selectedRouteIndex = -1;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  
  String? _mapStyle;
  
  // --- NEW: State for handling asynchronous jobs ---
  String? _jobId;
  Timer? _pollingTimer;

  final String _googleApiKey = ConfigService.instance.googleMapsApiKey;
  final String _apiBaseUrl = ConfigService.instance.apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    DefaultAssetBundle.of(context).loadString('assets/map_style.json').then((string) {
      _mapStyle = string;
    });
  }
  
  @override
  void dispose() {
    // NEW: Cancel the timer to prevent memory leaks when the widget is removed.
    _pollingTimer?.cancel();
    _mapController?.dispose();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<String?> _getReadableAddress(LatLng location) async {
    try {
      final uri = Uri.parse('$_apiBaseUrl/reverse-geocode?lat=${location.latitude}&lng=${location.longitude}');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['address'];
      }
    } catch (e) {
      print("Error getting readable address: $e");
    }
    return null;
  }

  Future<void> _getCurrentLocation() async {
    Location location = Location();
    bool serviceEnabled;
    PermissionStatus permissionGranted;
    LocationData locationData;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    locationData = await location.getLocation();
    if (locationData.latitude != null && locationData.longitude != null) {
      final currentLatLng = LatLng(locationData.latitude!, locationData.longitude!);
      setState(() {
        _currentLocation = currentLatLng;
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 15.0));
      });
      
      final address = await _getReadableAddress(currentLatLng);
      if (address != null && mounted) {
        setState(() {
          _originController.text = address;
        });
      } else {
        setState(() {
          _originController.text = "Lokasi Saat Ini";
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAddressSuggestions(String pattern) async {
    if (pattern.trim().isEmpty) {
      return [];
    }
    final Uri url = Uri.parse("$_apiBaseUrl/autocomplete-address?query=${Uri.encodeComponent(pattern)}");

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = data['predictions'] as List;
        return predictions.cast<Map<String, dynamic>>();
      } else {
        print('Failed to load address suggestions: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error fetching address suggestions: $e');
      return [];
    }
  }

  // --- REFACTORED: This function now starts the job and polling ---
  Future<void> _getRoute() async {
    if (_originController.text.isEmpty || _destinationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap isi alamat awal dan tujuan')),
      );
      return;
    }
    
    // Reset previous results and start loading
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Starting route analysis...';
      _markers = {};
      _polylines = {};
      _routeAlternatives = [];
      _selectedRouteIndex = -1;
      _pollingTimer?.cancel(); // Cancel any previous timer
    });

    try {
      final Uri apiUrl = Uri.parse("$_apiBaseUrl/calculate-routes");
      
      // 1. Initial POST request to start the job
      final response = await http.post(
        apiUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'origin_address': _originController.text,
          'destination_address': _destinationController.text,
          'mode': _selectedMode,
        }),
      );

      // 2. Check if the job was created successfully (202 Accepted)
      if (response.statusCode == 202) {
        final data = json.decode(response.body);
        _jobId = data['job_id'];
        
        if (_jobId != null) {
          // 3. Start polling for the result
          setState(() {
            _loadingMessage = 'Analyzing walkability...';
            _isSearchCardExpanded = false; // Collapse card after starting
          });
          _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
            _pollRouteStatus(_jobId!);
          });
        }
      } else {
        final error = json.decode(response.body);
        _showErrorAndStopLoading('Error: ${error['detail'] ?? 'Failed to start route calculation'}');
      }
    } catch (e) {
      _showErrorAndStopLoading('An error occurred: $e');
    }
  }

  // --- NEW: Function to poll the status endpoint ---
  Future<void> _pollRouteStatus(String jobId) async {
    try {
      final Uri statusUrl = Uri.parse("$_apiBaseUrl/routes/status/$jobId");
      final response = await http.get(statusUrl);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];

        if (status == 'completed') {
          _pollingTimer?.cancel(); // Stop polling
          final alternatives = data['data'] as List;

          if (alternatives.isNotEmpty) {
            alternatives.sort((a, b) => (b['average_walkability_score'] as num).compareTo(a['average_walkability_score'] as num));
            setState(() {
              _routeAlternatives = alternatives.take(3).map((e) => e as Map<String, dynamic>).toList();
              _isLoading = false; // Stop loading indicator
            });
            _selectRoute(0); // Select and display the best route
          } else {
            _showErrorAndStopLoading('No suitable routes were found.');
          }

        } else if (status == 'failed') {
          _pollingTimer?.cancel();
          final error = data['error'] ?? 'Route analysis failed.';
          _showErrorAndStopLoading('Error: $error');

        } else {
          // Still 'pending' or 'processing', do nothing and wait for the next poll.
          print('Route analysis status: $status');
        }
      } else {
        // Handle cases where the status check itself fails
        _pollingTimer?.cancel();
        _showErrorAndStopLoading('Failed to get route status.');
      }
    } catch (e) {
      _pollingTimer?.cancel();
      _showErrorAndStopLoading('An error occurred while checking status: $e');
    }
  }
  
  // --- NEW: Helper to centralize error handling and stopping the loading state ---
  void _showErrorAndStopLoading(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _displaySelectedRoutePolyline() {
    Set<Polyline> newPolylines = {};
    if (_selectedRouteIndex == -1 || _routeAlternatives.isEmpty) {
      setState(() {
        _polylines = newPolylines;
      });
      return;
    }

    final List<Color> colors = [Colors.green, Colors.amber, Colors.red];
    final PolylinePoints polylinePoints = PolylinePoints();
    final route = _routeAlternatives[_selectedRouteIndex];

    final List<PointLatLng> result = polylinePoints.decodePolyline(route['overview_polyline']);
    final List<LatLng> polylineCoordinates = result.map((point) => LatLng(point.latitude, point.longitude)).toList();

    newPolylines.add(Polyline(
      polylineId: PolylineId('route_$_selectedRouteIndex'),
      color: colors[_selectedRouteIndex],
      width: 7,
      points: polylineCoordinates,
    ));

    setState(() {
      _polylines = newPolylines;
    });
  }

  Future<void> _selectRoute(int index) async {
    if (index >= _routeAlternatives.length) return;

    setState(() {
      _selectedRouteIndex = index;
    });

    _displaySelectedRoutePolyline();

    final selectedRoute = _routeAlternatives[index];
    final points = selectedRoute['points_analyzed'] as List;
    final List<Color> colors = [Colors.green, Colors.amber, Colors.red];
    final Color routeColor = colors[index];
    
    Set<Marker> newMarkers = {};

    if (points.isNotEmpty) {
      final polylineCoordinates = PolylinePoints().decodePolyline(selectedRoute['overview_polyline']).map((p) => LatLng(p.latitude, p.longitude)).toList();
       if (polylineCoordinates.isNotEmpty) {
          newMarkers.add(Marker(
            markerId: const MarkerId('start'),
            position: polylineCoordinates.first,
            icon: await _createCustomMarker(Colors.green, isStart: true),
          ));
          newMarkers.add(Marker(
            markerId: const MarkerId('end'),
            position: polylineCoordinates.last,
            icon: await _createCustomMarker(Colors.grey),
          ));
          // Animate camera to fit the route
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_createLatLngBounds(polylineCoordinates), 50));
       }
    }
    
    await _addPointOfInterestMarkers(newMarkers, points, routeColor);

    setState(() {
      _markers = newMarkers;
    });
  }

  Future<void> _addPointOfInterestMarkers(Set<Marker> markers, List<dynamic> points, Color color) async {
    for (var point in points) {
      markers.add(
        Marker(
          markerId: MarkerId('${point['latitude']}-${point['longitude']}'),
          position: LatLng(
            (point['latitude'] as num).toDouble(),
            (point['longitude'] as num).toDouble()
          ),
          icon: await _createCustomMarker(color.withOpacity(0.7)),
          infoWindow: InfoWindow(
            title: 'Skor: ${point['walkability_score']}',
          ),
        ),
      );
    }
  }

  LatLngBounds _createLatLngBounds(List<LatLng> points) {
    double? minLat, maxLat, minLng, maxLng;

    for (final point in points) {
      if (minLat == null || point.latitude < minLat) minLat = point.latitude;
      if (maxLat == null || point.latitude > maxLat) maxLat = point.latitude;
      if (minLng == null || point.longitude < minLng) minLng = point.longitude;
      if (maxLng == null || point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }

  Future<BitmapDescriptor> _createCustomMarker(Color color, {bool isStart = false}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final Paint paint = Paint()..color = color;
    const double radius = 20.0;

    canvas.drawCircle(const Offset(radius, radius), radius, paint..color = color.withOpacity(0.3));
    canvas.drawCircle(const Offset(radius, radius), radius / (isStart ? 1.5 : 2.5), paint..color = color);

    final img = await pictureRecorder.endRecording().toImage(radius.toInt() * 2, radius.toInt() * 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _showRouteDetails(int index) {
    if (index == -1) return;

    final points = _routeAlternatives[index]['points_analyzed'] as List;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Text(
                    "Detail Titik",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: points.length,
                      itemBuilder: (context, index) {
                        final point = points[index];
                        final List<dynamic> labels = point['detected_labels'] ?? [];

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8.0),
                                  child: Image.network(
                                    point['photo_url'],
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => const Icon(Icons.error, size: 40),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Skor: ${point['walkability_score']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      if (labels.isNotEmpty)
                                        Wrap(
                                          spacing: 6.0,
                                          runSpacing: 4.0,
                                          children: labels.map((label) => Chip(
                                            label: Text(label.toString(), style: const TextStyle(fontSize: 10)),
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            backgroundColor: Colors.grey[200],
                                          )).toList(),
                                        )
                                      else
                                        Text(
                                          'Lat: ${(point['latitude'] as num).toStringAsFixed(5)}, Lng: ${(point['longitude'] as num).toStringAsFixed(5)}',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _mapController!.setMapStyle(_mapStyle);
            },
            onTap: (_) {
              FocusScope.of(context).unfocus();
              setState(() {
                _isSearchCardExpanded = false;
              });
            },
            initialCameraPosition: CameraPosition(
              target: _currentLocation ?? const LatLng(-7.2575, 112.7521),
              zoom: 15.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers,
            polylines: _polylines,
            zoomControlsEnabled: false,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSearchCard(),
                  if (_isLoading)
                     // UPDATED: Show a more informative loading indicator
                    Card(
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(width: 16),
                            Text(_loadingMessage),
                          ],
                        ),
                      ),
                    ),
                  if (_routeAlternatives.isNotEmpty)
                    _buildRouteInfoCards(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Card(
      elevation: 8.0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          child: _isSearchCardExpanded
              ? _buildExpandedContent()
              : _buildCollapsedContent(),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent() {
    return InkWell(
      onTap: () {
        setState(() {
          _isSearchCardExpanded = true;
        });
      },
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          children: [
            Icon(Icons.search, color: Colors.grey),
            SizedBox(width: 12),
            Text("Search Maps", style: TextStyle(color: Colors.grey, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAddressTypeAheadField(_originController, "Starting Point", Icons.my_location, Colors.green),
        const Divider(),
        _buildAddressTypeAheadField(_destinationController, "Destination", Icons.location_on, Colors.grey),
        const SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ChoiceChip(
              label: const Text('Rute Optimal'),
              selected: _selectedMode == 'distance_walkability',
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedMode = 'distance_walkability';
                  });
                }
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: Colors.green,
              labelStyle: TextStyle(
                color: _selectedMode == 'distance_walkability' ? Colors.white : Colors.black,
              ),
            ),
            ChoiceChip(
              label: const Text('Rute Rindang'),
              selected: _selectedMode == 'shady_route',
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedMode = 'shady_route';
                  });
                }
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: Colors.green,
              labelStyle: TextStyle(
                color: _selectedMode == 'shady_route' ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _getRoute,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            child: const Text('Cari Rute', style: TextStyle(fontSize: 15)),
          ),
        )
      ],
    );
  }

  Widget _buildAddressTypeAheadField(TextEditingController controller, String hint, IconData icon, Color iconColor) {
    return TypeAheadField<Map<String, dynamic>>(
      controller: controller,
      suggestionsCallback: _fetchAddressSuggestions,
      itemBuilder: (context, suggestion) {
        final description = suggestion['description'] as String?;
        return ListTile(
          title: Text(description ?? 'Invalid Address', style: const TextStyle(fontSize: 14)),
        );
      },
      onSelected: (suggestion) {
        final description = suggestion['description'] as String?;
        if (description != null) {
          controller.text = description;
        }
      },
      builder: (context, controller, focusNode) => TextField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          contentPadding: const EdgeInsets.symmetric(vertical: 12.0),
        ),
      ),
      emptyBuilder: (context) => const Padding(
        padding: EdgeInsets.all(12.0),
        child: Text('Tidak ada alamat yang cocok.', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _buildRouteInfoCards() {
    final List<Color> colors = [Colors.green, Colors.amber, Colors.red];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_routeAlternatives.length, (index) {
        final route = _routeAlternatives[index];
        return Expanded(
          child: GestureDetector(
            onTap: () {
              _selectRoute(index);
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              color: const Color(0xFFFFFFFF),
              elevation: 6.0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
                side: BorderSide(
                  color: _selectedRouteIndex == index ? colors[index] : Colors.grey.shade300,
                  width: _selectedRouteIndex == index ? 2.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Rute ${index + 1}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_walk, color: colors[index], size: 18),
                        const SizedBox(width: 4),
                        Text(
                          "${(route['average_walkability_score'] as num).toStringAsFixed(1)}",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors[index],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _showRouteDetails(index),
                      child: Text(
                        "Detail",
                        style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, decoration: TextDecoration.underline),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
