import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config_service.dart';

class CreateReportPage extends StatefulWidget {
  const CreateReportPage({super.key});

  @override
  State<CreateReportPage> createState() => _CreateReportPageState();
}

class _CreateReportPageState extends State<CreateReportPage> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedCategory;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isSubmitting = false;
  LatLng? _reportLocation; 
  String? _address;
  XFile? _imageFile;

  final String _apiBaseUrl = ConfigService.instance.apiBaseUrl;

  final List<String> _categories = [
    'Damaged Sidewalk', 'Blocked by Vendors', 'Illegal Parking',
    'Flooding / Puddles', 'Construction', 'Other'
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }
  
  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _address = "Getting location...");
    Location location = Location();
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) throw Exception('Location service not enabled.');
      }
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) throw Exception('Location permission denied.');
      }

      final locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        final currentLatLng = LatLng(locationData.latitude!, locationData.longitude!);
        setState(() {
          _reportLocation = currentLatLng;
        });
        await _getReadableAddress(currentLatLng);
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar('Failed to get location. Please ensure GPS is enabled.');
      setState(() => _address = "Could not get location");
    }
  }

  Future<void> _getReadableAddress(LatLng location) async {
    setState(() => _address = "Finding address...");
    try {
      final uri = Uri.parse('$_apiBaseUrl/reverse-geocode?lat=${location.latitude}&lng=${location.longitude}');
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => _address = data['address']);
      } else {
        if (mounted) setState(() => _address = "Could not find address");
      }
    } catch (e) {
      if (mounted) setState(() => _address = "Could not find address");
    }
  }

  void _showLocationPicker() async {
    if (_reportLocation == null) {
      _showErrorSnackBar("Current location not available yet.");
      return;
    }

    final LatLng? selectedLocation = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LocationPicker(initialLocation: _reportLocation!),
    );

    if (selectedLocation != null) {
      setState(() {
        _reportLocation = selectedLocation;
      });
      await _getReadableAddress(selectedLocation);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 1024);
      if (pickedFile != null) {
        setState(() => _imageFile = pickedFile);
      }
    } catch (e) {
      if(mounted) _showErrorSnackBar('Could not access photos or camera.');
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    
    if (_reportLocation == null) {
      _showErrorSnackBar('Location not found, cannot submit report.');
      return;
    }
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showErrorSnackBar('You must be logged in to create a report.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final request = http.MultipartRequest('POST', Uri.parse("$_apiBaseUrl/reports"));

      request.fields['user_id'] = user.id;
      request.fields['category'] = _selectedCategory!;
      request.fields['latitude'] = _reportLocation!.latitude.toString();
      request.fields['longitude'] = _reportLocation!.longitude.toString();
      if (_descriptionController.text.isNotEmpty) {
        request.fields['description'] = _descriptionController.text;
      }

      if (_imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('file', _imageFile!.path));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted successfully!')),
        );
        Navigator.of(context).pop(true);
      } else {
        final error = json.decode(response.body);
        _showErrorSnackBar(error['detail'] ?? 'Failed to submit report');
      }
    } catch (e) {
      _showErrorSnackBar('An error occurred: $e');
    } finally {
      if(mounted) setState(() => _isSubmitting = false);
    }
  }
  
  void _showErrorSnackBar(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Create New Report', style: textTheme.titleLarge),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: <Widget>[
            _buildSectionTitle('1. Report Details', textTheme),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              hint: const Text('Select Issue Category'),
              decoration: _inputDecoration(),
              validator: (value) => value == null ? 'Category is required' : null,
              onChanged: (String? newValue) {
                setState(() => _selectedCategory = newValue);
              },
              items: _categories.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: _inputDecoration(
                hintText: 'Add an optional description...',
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('2. Attach Photo (Optional)', textTheme),
            const SizedBox(height: 16),
            _buildPhotoPicker(),
            const SizedBox(height: 24),
            _buildSectionTitle('3. Location', textTheme),
            const SizedBox(height: 8),
            _buildLocationCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)
          ),
          child: _isSubmitting
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send, size: 20),
                    SizedBox(width: 12),
                    Text('Submit Report'),
                  ],
                ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({String? hintText, bool alignLabelWithHint = false}) {
    return InputDecoration(
      hintText: hintText,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.green, width: 2),
      ),
    );
  }

  Widget _buildSectionTitle(String title, TextTheme textTheme) {
    return Text(
      title,
      style: textTheme.titleMedium,
    );
  }

  Widget _buildPhotoPicker() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: _imageFile == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 40),
                const SizedBox(height: 8),
                Text('Add a photo of the issue', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Camera'),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ],
                )
              ],
            )
          : Stack(
              alignment: Alignment.topRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.file(
                    File(_imageFile!.path),
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => setState(() => _imageFile = null),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLocationCard() {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300)
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.location_on, color: Colors.green, size: 28),
        title: Text('Report Location', style: textTheme.titleSmall),
        subtitle: Text(_address ?? 'Getting location...', style: textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
        trailing: IconButton(
          icon: const Icon(Icons.edit_location_alt_outlined),
          onPressed: _showLocationPicker,
          tooltip: 'Change Location',
        ),
      ),
    );
  }
}

class LocationPicker extends StatefulWidget {
  final LatLng initialLocation;
  const LocationPicker({super.key, required this.initialLocation});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late LatLng _pickedLocation;
  
  @override
  void initState() {
    super.initState();
    _pickedLocation = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Move the map to select a location',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: widget.initialLocation,
                    zoom: 17,
                  ),
                  onCameraMove: (CameraPosition position) {
                    setState(() {
                      _pickedLocation = position.target;
                    });
                  },
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                     Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
                     Factory<ScaleGestureRecognizer>(() => ScaleGestureRecognizer()),
                     Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
                     Factory<VerticalDragGestureRecognizer>(() => VerticalDragGestureRecognizer()),
                  },
                ),
                const Center(
                  child: Padding(
                    // Padding to offset the icon so the tip is in the center
                    padding: EdgeInsets.only(bottom: 40.0),
                    child: Icon(
                      Icons.location_pin,
                      size: 40,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                Navigator.of(context).pop(_pickedLocation);
              },
              child: const Text('Confirm Location'),
            ),
          ),
        ],
      ),
    );
  }
}
