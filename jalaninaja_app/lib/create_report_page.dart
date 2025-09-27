import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';

import 'api_service.dart';

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

  final List<String> _categories = [
    'Damaged Sidewalk', 'Blocked by Vendors', 'Illegal Parking',
    'Flooding / Puddles', 'Construction', 'No Sidewalk', 'Poor Lighting', 'Other'
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
      final address = await ApiService.instance.reverseGeocode(location.latitude, location.longitude);
      if (mounted) setState(() => _address = address);
    } catch (e) {
      if (mounted) setState(() => _address = "Could not find address");
    }
  }

  // FIX: This function is now simplified as it only handles one source.
  Future<void> _takePicture() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1024);
      if (pickedFile != null) {
        setState(() => _imageFile = pickedFile);
      }
    } catch (e) {
      if(mounted) _showErrorSnackBar('Could not access camera.');
    }
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    
    // FIX: Added validation to ensure an image has been selected.
    if (_imageFile == null) {
      _showErrorSnackBar('A photo is required to submit a report.');
      return;
    }

    if (_reportLocation == null) {
      _showErrorSnackBar('Location not found, cannot submit report.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiService.instance.createReport(
        category: _selectedCategory!,
        description: _descriptionController.text,
        latitude: _reportLocation!.latitude,
        longitude: _reportLocation!.longitude,
        imageFile: _imageFile,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report submitted successfully! You earned 10 points!')),
      );
      Navigator.of(context).pop(true);

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
            // FIX: Updated section title to reflect photo is mandatory.
            _buildSectionTitle('2. Attach Photo', textTheme),
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
          // FIX: Simplified the UI to only show one button for taking a picture.
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.camera_alt_outlined, color: Colors.grey, size: 40),
                const SizedBox(height: 8),
                Text('A photo of the issue is required', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Picture'),
                  onPressed: _takePicture,
                   style: ElevatedButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                ),
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
        // FIX: Removed the trailing IconButton to prevent location changes.
        trailing: null,
      ),
    );
  }
}

