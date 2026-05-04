import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';

class MatricVerificationPage extends StatefulWidget {
  const MatricVerificationPage({super.key});

  @override
  State<MatricVerificationPage> createState() => _MatricVerificationPageState();
}

class _MatricVerificationPageState extends State<MatricVerificationPage> {
  File? _image;
  bool _isScanning = false;
  String? _errorMsg;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file != null) {
      setState(() {
        _image = File(file.path);
        _errorMsg = null;
      });
    }
  }

  Future<void> _scanMatricCard() async {
    if (_image == null) {
      setState(() => _errorMsg = "Please take a photo first.");
      return;
    }
    final user = AuthService.instance.currentUser;
    if (user == null) {
      setState(() => _errorMsg = "You must be logged in.");
      return;
    }

    setState(() => _isScanning = true);
    try {
      // 1. Upload to matric_cards/{uid}.jpg. The server-side
      //    verifyMatricCard function reads from this exact path.
      final ref = FirebaseStorage.instance
          .ref()
          .child('matric_cards')
          .child('${user.uid}.jpg');
      await ref.putFile(_image!);

      // 2. Ask the Cloud Function to verify the card. It runs Gemini
      //    server-side and writes isVerified / matricNumber to the user
      //    doc via the admin SDK on success.
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyMatricCard')
          .call();

      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification Successful! Welcome.')),
        );
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        setState(() {
          _errorMsg = data['reason'] is String
              ? data['reason'] as String
              : 'Verification failed.';
        });
      }
    } catch (e) {
      setState(() => _errorMsg = "Error during scanning: $e");
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Identity")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "To ensure safety, please upload a photo of your USIM Matric Card.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),

            //Image Preview Area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[100],
                ),
                child: _image != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_image!, fit: BoxFit.cover),
                      )
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              "Tap to take photo",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                "Your ID is used strictly for identity verification. "
                "It is visible only to Admins and will not be shared publicly.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),

            // Buttons
            if (_image == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text("Take Photo"),
                onPressed: () => _pickImage(ImageSource.camera),
              )
            else
              ElevatedButton.icon(
                icon: _isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Icon(Icons.check_circle),
                label: Text(
                  _isScanning ? "Verifying..." : "Submit for Verification",
                ),
                onPressed: _isScanning ? null : _scanMatricCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),

            const SizedBox(height: 16),

            TextButton.icon(
              icon: const Icon(Icons.logout, size: 20, color: Colors.grey),
              label: const Text(
                "Cancel & Logout",
                style: TextStyle(color: Colors.grey),
              ),
              onPressed: () async {
                await AuthService.instance.logout();
              },
            ),

            if (_errorMsg != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMsg!,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () => _pickImage(ImageSource.camera),
                child: const Text("Try Again"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
