import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import 'api_service.dart';
import 'models.dart' as app_models;
import 'report_detail_page.dart';
import 'widgets/report_card.dart';

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
  String _loadingMessage = 'Calculating...';
  bool _isSearchCardExpanded = false;
  String _selectedMode = "distance_walkability";

  List<app_models.RouteAlternative> _routeAlternatives = [];
  int _selectedRouteIndex = -1;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  
  app_models.AnalyzedPoint? _selectedPoint;
  
  String? _mapStyle;
  String? _jobId;
  Timer? _pollingTimer;
  bool _isShowingBottomSheet = false;

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
    _pollingTimer?.cancel();
    _mapController?.dispose();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    Location location = Location();
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) return;
      }
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) return;
      }

      final locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        final currentLatLng = LatLng(locationData.latitude!, locationData.longitude!);
        setState(() {
          _currentLocation = currentLatLng;
          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 15.0));
        });
        
        final address = await ApiService.instance.reverseGeocode(currentLatLng.latitude, currentLatLng.longitude);
        if (mounted) {
          setState(() => _originController.text = address);
        }
      }
    } catch (e) {
        print("Error getting location: $e");
        if(mounted) {
          setState(() => _originController.text = "Current Location");
        }
    }
  }

  Future<List<app_models.PlaceAutocomplete>> _fetchAddressSuggestions(String pattern) async {
      if (pattern.trim().isEmpty) return [];
      return await ApiService.instance.autocompleteAddress(
        pattern,
        lat: _currentLocation?.latitude,
        lng: _currentLocation?.longitude,
      );
  }

  Future<void> _getRoute() async {
    if (_originController.text.isEmpty || _destinationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in origin and destination')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Starting route analysis...';
      _markers = {};
      _polylines = {};
      _routeAlternatives = [];
      _selectedRouteIndex = -1;
      _selectedPoint = null;
      _pollingTimer?.cancel();
    });

    try {
      _jobId = await ApiService.instance.calculateRoute(
        origin: _originController.text,
        destination: _destinationController.text,
        mode: _selectedMode,
      );
      
      if (_jobId != null) {
        setState(() {
          _loadingMessage = 'Analyzing walkability...';
          _isSearchCardExpanded = false;
        });
        _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          _pollRouteStatus(_jobId!);
        });
      } else {
        _showErrorAndStopLoading('Failed to start route calculation.');
      }
    } catch (e) {
      _showErrorAndStopLoading('An error occurred: $e');
    }
  }

  double _calculateWalkabilityScoreForPoint(app_models.AnalyzedPoint point, String mode) {
    double score = 50.0;
    if (point.detectedLabels.contains('sidewalk')) {
      score += 20;
      double dynamicBonus = min(point.sidewalkArea, 25);
      score += dynamicBonus;
    } else {
      if (point.isResidential) {
        score -= 15;
      } else {
        score -= 30;
      }
    }

    if (mode == 'shady_route') {
      score += min(point.treeCount * 5, 20);
    }

    return max(0, min(100, score));
  }

  List<app_models.RouteAlternative> _recalculateScoresForAlternatives(
    List<app_models.RouteAlternative> alternatives,
    String mode
  ) {
    for (var route in alternatives) {
      double totalScore = 0;
      if (route.pointsAnalyzed.isEmpty) {
        route.averageWalkabilityScore = 0;
        continue;
      }
      
      for (var point in route.pointsAnalyzed) {
        point.walkabilityScore = _calculateWalkabilityScoreForPoint(point, mode);
        totalScore += point.walkabilityScore;
      }
      
      route.averageWalkabilityScore = totalScore / route.pointsAnalyzed.length;
    }
    return alternatives;
  }

  Future<void> _pollRouteStatus(String jobId) async {
    try {
      final result = await ApiService.instance.pollRouteStatus(jobId);

      if (result.status == 'completed') {
        _pollingTimer?.cancel();
        List<app_models.RouteAlternative>? alternatives = result.data;

        if (alternatives != null && alternatives.isNotEmpty) {
          
          alternatives = _recalculateScoresForAlternatives(alternatives, _selectedMode);
          
          alternatives.sort((a, b) => b.averageWalkabilityScore.compareTo(a.averageWalkabilityScore));

          setState(() {
            _routeAlternatives = alternatives!.take(3).toList();
            _isLoading = false;
          });
          _selectRoute(0);
        } else {
          _showErrorAndStopLoading('No suitable routes were found.');
        }

      } else if (result.status == 'failed') {
        _pollingTimer?.cancel();
        final error = result.error ?? 'Route analysis failed.';
        _showErrorAndStopLoading('Error: $error');
      }
    } catch (e) {
      _pollingTimer?.cancel();
      _showErrorAndStopLoading('An error occurred while checking status: $e');
    }
  }

  void _showErrorAndStopLoading(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _isLoading = false);
    }
  }
  
  void _displaySelectedRoutePolyline() {
    Set<Polyline> newPolylines = {};
    if (_selectedRouteIndex == -1 || _routeAlternatives.isEmpty) {
      setState(() => _polylines = newPolylines);
      return;
    }

    final List<Color> colors = [Colors.green, Colors.amber, Colors.red];
    final PolylinePoints polylinePoints = PolylinePoints();
    final route = _routeAlternatives[_selectedRouteIndex];

    final List<PointLatLng> result = polylinePoints.decodePolyline(route.overviewPolyline);
    final List<LatLng> polylineCoordinates = result.map((point) => LatLng(point.latitude, point.longitude)).toList();

    newPolylines.add(Polyline(
      polylineId: PolylineId('route_$_selectedRouteIndex'),
      color: colors[_selectedRouteIndex],
      width: 7,
      points: polylineCoordinates,
    ));

    setState(() => _polylines = newPolylines);
  }

  Future<void> _selectRoute(int index) async {
    if (index >= _routeAlternatives.length) return;

    setState(() {
      _selectedRouteIndex = index;
      _selectedPoint = null;
    });

    _displaySelectedRoutePolyline();

    final selectedRoute = _routeAlternatives[index];
    final points = selectedRoute.pointsAnalyzed;
    final List<Color> colors = [Colors.green, Colors.amber, Colors.red];
    final Color routeColor = colors[index];
    
    Set<Marker> newMarkers = {};

    if (points.isNotEmpty) {
      final polylineCoordinates = PolylinePoints().decodePolyline(selectedRoute.overviewPolyline).map((p) => LatLng(p.latitude, p.longitude)).toList();
      if (polylineCoordinates.isNotEmpty) {
          newMarkers.add(Marker(
            markerId: const MarkerId('start'),
            position: polylineCoordinates.first,
            icon: await _createCustomMarker(Colors.green, isStart: true),
          ));
          newMarkers.add(Marker(
            markerId: const MarkerId('end'),
            position: polylineCoordinates.last,
            icon: await _createCustomMarker(Colors.grey.shade700, isEnd: true),
          ));
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(_createLatLngBounds(polylineCoordinates), 50));
      }
    }
    
    await _addPointOfInterestMarkers(newMarkers, points, routeColor);

    setState(() => _markers = newMarkers);
  }

  Future<void> _addPointOfInterestMarkers(Set<Marker> markers, List<app_models.AnalyzedPoint> points, Color color) async {
    for (var point in points) {
      markers.add(
        Marker(
          markerId: MarkerId('${point.latitude}-${point.longitude}'),
          position: LatLng(point.latitude, point.longitude),
          icon: await _createCustomMarker(color),
          onTap: () {
            setState(() => _selectedPoint = point);
          }
        ),
      );
    }
  }

  LatLngBounds _createLatLngBounds(List<LatLng> points) {
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  Future<BitmapDescriptor> _createCustomMarker(Color color, {bool isStart = false, bool isEnd = false}) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    const double radius = 22.0;
    final Offset center = const Offset(radius, radius);
    final double imageSize = (radius * 2) + 4; // Add padding for shadow

    // 1. Draw Shadow
    final Paint shadowPaint = Paint()..color = Colors.black.withOpacity(0.4);
    canvas.drawCircle(Offset(center.dx + 2, center.dy + 2), radius, shadowPaint);

    // 2. Draw White Border Background
    final Paint borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, radius, borderPaint);

    // 3. Draw Main Color Fill
    final Paint mainPaint = Paint()..color = color;
    canvas.drawCircle(center, radius - 4, mainPaint); // Create a 4px white border

    // 4. Draw Icon if it's a regular route point
    if (!isStart && !isEnd) {
      const IconData icon = Icons.directions_walk;
      TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 24.0,
          fontFamily: icon.fontFamily,
          color: Colors.white,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
      );
    }

    final img = await pictureRecorder.endRecording().toImage(imageSize.toInt(), imageSize.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }
  
  Future<void> _showCustomBottomSheet({required BuildContext context, required WidgetBuilder builder}) async {
    if (!mounted) return;
    setState(() {
      _isShowingBottomSheet = true;
    });

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isShowingBottomSheet = false;
        });
      }
    });
  }

  Future<void> _fetchAndShowNearbyReports(LatLng location) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final reports = await ApiService.instance.getNearbyReports(location.latitude, location.longitude);
      Navigator.of(context).pop(); 
      if (!mounted) return;
      
      _showCustomBottomSheet(
        context: context,
        builder: (_) => NearbyReportsSheet(reports: reports),
      );

    } catch (e) {
      Navigator.of(context).pop(); 
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to get reports: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showFullImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            panEnabled: true,
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                return progress == null ? child : const Center(child: CircularProgressIndicator());
              },
              errorBuilder: (c, e, s) => const Center(child: Icon(Icons.error, color: Colors.white, size: 50)),
            ),
          ),
        ),
      ),
    );
  }

  void _showScoringExplanationBottomSheet() {
    _showCustomBottomSheet(
      context: context,
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How is the Walkability Score Calculated?', style: textTheme.titleLarge),
              const SizedBox(height: 24),
              const _ScoreExplanationTile(
                icon: Icons.add_circle,
                color: Colors.blue,
                title: 'Base Score: 50 points',
                subtitle: 'Every location starts with a neutral base score.',
              ),
              const _ScoreExplanationTile(
                icon: Icons.add_circle,
                color: Colors.green,
                title: 'Sidewalk Detected: +20 points',
                subtitle: 'Bonus points are awarded if a sidewalk is present.',
              ),
               const _ScoreExplanationTile(
                icon: Icons.add_circle,
                color: Colors.green,
                title: 'Sidewalk Size: Up to +25 points',
                subtitle: 'Larger sidewalks get a higher bonus, encouraging wider pedestrian paths.',
              ),
              const _ScoreExplanationTile(
                icon: Icons.remove_circle,
                color: Colors.red,
                title: 'No Sidewalk Penalty: -30 points',
                subtitle: 'A significant penalty is applied if no sidewalk is found on a non-residential road.',
              ),
              const _ScoreExplanationTile(
                icon: Icons.park,
                color: Colors.teal,
                title: 'Shady Route Bonus: Up to +20 points',
                subtitle: 'When using the "Shady Route" mode, points are added for the number of trees detected, promoting cooler walks.',
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
  
  void _showRouteDetails(int index) {
    if (index == -1) return;
    final points = _routeAlternatives[index].pointsAnalyzed;
    final textTheme = Theme.of(context).textTheme;

    _showCustomBottomSheet(
      context: context,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text("Route Details", style: textTheme.titleLarge),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: points.length,
                      itemBuilder: (context, index) {
                        final point = points[index];
                        final List<dynamic> labels = point.detectedLabels;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          elevation: 1,
                          shadowColor: Colors.black.withOpacity(0.05),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _showFullImageDialog(point.photoUrl!),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8.0),
                                    child: Image.network(
                                      point.photoUrl!,
                                      width: 80, height: 80, fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Container(
                                        width: 80, height: 80, color: Colors.grey[200],
                                        child: const Icon(Icons.broken_image, color: Colors.grey)
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'Score: ${point.walkabilityScore.round()}',
                                            style: textTheme.titleMedium
                                          ),
                                          const SizedBox(width: 8),
                                          InkWell(
                                            onTap: _showScoringExplanationBottomSheet,
                                            child: const Icon(Icons.info_outline, size: 20, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      if (labels.isNotEmpty)
                                        Wrap(
                                          spacing: 6.0,
                                          runSpacing: 4.0,
                                          children: labels.map((label) => Chip(
                                            label: Text(label.toString(), style: const TextStyle(fontSize: 11)),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            backgroundColor: Colors.grey[200],
                                            side: BorderSide.none,
                                          )).toList(),
                                        )
                                      else
                                        Text('No objects detected.', style: textTheme.bodySmall),
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        height: 32,
                                        child: TextButton.icon(
                                           style: TextButton.styleFrom(
                                            foregroundColor: Theme.of(context).colorScheme.primary,
                                            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.report_problem_outlined, size: 16),
                                          label: const Text('See Nearby Reports', style: TextStyle(fontSize: 12)),
                                          onPressed: () {
                                            Navigator.of(context).pop();
                                            _fetchAndShowNearbyReports(point.toLatLng());
                                          },
                                        ),
                                      )
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
                _selectedPoint = null;
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
            padding: EdgeInsets.only(bottom: _routeAlternatives.isNotEmpty ? 120 : 0),
          ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: _buildSearchCard(),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Visibility(
                    visible: !_isShowingBottomSheet,
                    child: RepaintBoundary(
                      child: _isLoading
                          ? Center(
                              child: Card(
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
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_selectedPoint != null)
                                  _buildPointInfoCard(_selectedPoint!),
                                if (_routeAlternatives.isNotEmpty)
                                  _buildRouteInfoCards(),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
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
      onTap: () => setState(() => _isSearchCardExpanded = true),
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
              label: const Text('Optimal Route'),
              selected: _selectedMode == 'distance_walkability',
              onSelected: (selected) {
                if(selected) setState(() => _selectedMode = 'distance_walkability');
              },
              backgroundColor: Colors.grey.shade200, selectedColor: Colors.green,
              labelStyle: TextStyle(color: _selectedMode == 'distance_walkability' ? Colors.white : Colors.black),
            ),
            ChoiceChip(
              label: const Text('Shady Route'),
              selected: _selectedMode == 'shady_route',
              onSelected: (selected) {
                 if(selected) setState(() => _selectedMode = 'shady_route');
              },
              backgroundColor: Colors.grey.shade200, selectedColor: Colors.green,
              labelStyle: TextStyle(color: _selectedMode == 'shady_route' ? Colors.white : Colors.black),
            ),
          ],
        ),
        const SizedBox(height: 8.0),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _getRoute,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
            ),
            child: const Text('Find Route', style: TextStyle(fontSize: 15)),
          ),
        )
      ],
    );
  }

  Widget _buildAddressTypeAheadField(TextEditingController controller, String hint, IconData icon, Color iconColor) {
    return TypeAheadField<app_models.PlaceAutocomplete>(
      controller: controller,
      suggestionsCallback: _fetchAddressSuggestions,
      itemBuilder: (context, suggestion) => ListTile(
        title: Text(suggestion.mainText, style: const TextStyle(fontSize: 14)),
        subtitle: Text(suggestion.secondaryText, style: const TextStyle(fontSize: 12)),
      ),
      onSelected: (suggestion) => controller.text = suggestion.description,
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
        child: Text('No matching addresses found.', style: TextStyle(fontSize: 14)),
      ),
    );
  }

  Widget _buildRouteInfoCards() {
    final List<Color> colors = [Colors.green, Colors.amber.shade600, Colors.red.shade600];
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: List.generate(_routeAlternatives.length, (index) {
        final route = _routeAlternatives[index];
        final isSelected = _selectedRouteIndex == index;
        final rankText = index == 0 ? "Best Route" : "Alternative";

        return Expanded(
          child: GestureDetector(
            onTap: () => _selectRoute(index),
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 4.0),
              color: isSelected ? const Color(0xFFF1F8E9) : Colors.white,
              elevation: isSelected ? 6 : 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
                side: BorderSide(
                  color: isSelected ? colors[index] : Colors.grey.shade200,
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      rankText,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.black87 : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          route.averageWalkabilityScore.round().toString(),
                          style: textTheme.titleLarge?.copyWith(
                            color: colors[index],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "/100",
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => _showRouteDetails(index),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text("View Details"),
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

  Widget _buildPointInfoCard(app_models.AnalyzedPoint point) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  point.photoUrl!, height: 120, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (c,e,s) => const SizedBox(height: 120, child: Center(child: Icon(Icons.broken_image))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4.0),
                child: IconButton.filled(
                  constraints: const BoxConstraints(), padding: const EdgeInsets.all(4),
                  style: IconButton.styleFrom(backgroundColor: Colors.black45),
                  icon: const Icon(Icons.close, size: 18, color: Colors.white), 
                  onPressed: () => setState(() => _selectedPoint = null),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Score: ${point.walkabilityScore.round()}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: () => _fetchAndShowNearbyReports(point.toLatLng()),
                  child: const Text("See Reports"),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class NearbyReportsSheet extends StatefulWidget {
  final List<app_models.Report> reports;
  const NearbyReportsSheet({super.key, required this.reports});

  @override
  State<NearbyReportsSheet> createState() => _NearbyReportsSheetState();
}

class _NearbyReportsSheetState extends State<NearbyReportsSheet> {
  Set<int> _votingReportIds = {}; 

  Future<void> _handleVote(app_models.Report report) async {
    if (_votingReportIds.contains(report.reportId)) return;

    setState(() {
      _votingReportIds.add(report.reportId);
    });

    try {
      if (report.isUpvoted) {
        await ApiService.instance.removeVote(report.reportId);
      } else {
        await ApiService.instance.upvoteReport(report.reportId);
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Vote failed: $e")));
    } finally {
      if(mounted) {
        setState(() {
          _votingReportIds.remove(report.reportId);
          report.isUpvoted = !report.isUpvoted;
          report.upvoteCount += report.isUpvoted ? 1 : -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
              ),
              const Text("Nearby Reports", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: widget.reports.isEmpty
                    ? const Center(child: Text("No reports found in this area."))
                    : ListView.builder(
                        controller: controller,
                        itemCount: widget.reports.length,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemBuilder: (context, index) {
                          final report = widget.reports[index];
                          return ReportCard(
                            report: report,
                            showVoteButton: true,
                            onUpvote: () => _handleVote(report),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ReportDetailPage(initialReport: report),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScoreExplanationTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _ScoreExplanationTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

