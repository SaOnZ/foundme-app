import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
      setState(() => _errorMsg = "Please take a phot first.");
      return;
    }

    setState(() => _isScanning = true);

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null) throw "API Key missing";

      final model = GenerativeModel(
        model: 'gemini-2.0-flash-lite-001',
        apiKey: apiKey,
      );

      final imageBytes = await _image!.readAsBytes();
      final user = AuthService.instance.currentUser;

      // Prompt: Ask AI to verify if it's a USIM card
      final prompt = TextPart("""
      Analyze this image. It should be a University Student ID (Matric Card).
      
      1. Is this a valid student ID card? (True/False)
      2. Does it belong to a university named "USIM" or "Universiti Sains Islam Malaysia"?
      3. Extract the Student Name and Matric Number.
      
      RETURN JSON ONLY:
      {
        "is_valid_card": true,
        "is_usim": true,
        "name": "Student Name",
        "matric_no": "123456",
        "reason": "Clear USIM logo visible"
      }
      """);

      final response = await model.generateContent([
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)]),
      ]);

      final output = response.text;
      print("AI Verification: $output");

      if (output != null) {
        final startIndex = output.indexOf('{');
        final endIndex = output.lastIndexOf('}');
        if (startIndex != -1 && endIndex != -1) {
          final jsonStr = output.substring(startIndex, endIndex + 1);
          final data = jsonDecode(jsonStr);

          if (data['is_valid_card'] == true && data['is_usim'] == true) {
            final String scannedMatric = data['matric_no'];

            // Query Firestore for this specifi matric number
            final duplicateCheck = await FirebaseFirestore.instance
                .collection('users')
                .where('matricNumber', isEqualTo: scannedMatric)
                .get();

            // If we found adocument, and it's not the current user's document
            if (duplicateCheck.docs.isNotEmpty) {
              // Check if the duplicate belongs to someone else
              final existingUser = duplicateCheck.docs.first;
              if (existingUser.id != user!.uid) {
                setState(() {
                  _errorMsg =
                      "Security Alert: This Matric Card ($scannedMatric) is already registered to another account!";
                });
                return;
              }
            }

            // Upload the image to Firebase Storage
            String? matricUrl;
            try {
              final ref = FirebaseStorage.instance
                  .ref()
                  .child('matric_cards')
                  .child('${user!.uid}.jpg');

              await ref.putFile(_image!);
              matricUrl = await ref.getDownloadURL();
            } catch (e) {
              print("Failed to upload matric card: $e");
              setState(
                () => _errorMsg =
                    "Failed to uplaod photo. Check internet/permissions.",
              );
              return;
            }

            if (matricUrl == null) {
              setState(() => _errorMsg = "Upload failed (Url is null).");
              return;
            }

            // SUCCESS: Verify the user in Firestore
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user!.uid)
                .update({
                  'isVerified': true,
                  'matricNumber': scannedMatric,
                  'matricName': data['name'],
                  'matricCardUrl': matricUrl,
                  'verificationDate': FieldValue.serverTimestamp(),
                });

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Verification Successful! Welcome.'),
                ),
              );
              // Go to Home
              Navigator.of(context).pushReplacementNamed('/home');
            }
          } else {
            setState(() {
              _errorMsg =
                  "Verification Failed: ${data['reason']}. Please user a clear USIM Matric Card.";
            });
          }
        }
      }
    } catch (e) {
      setState(() => _errorMsg = "Error during scanning: $e");
    } finally {
      setState(() => _isScanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("verify Identity")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "to ensure safety, please upload a photo of your USIM Matric Card.",
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
                "🔒 Your ID is used strictly for identity verification. "
                "It is visible only to Admins and will not be shared publicly.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),

            // Buttons
            if (_image == null)
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text("take Photo"),
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
                  _isScanning ? "verifying..." : "Submit for Verification",
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
