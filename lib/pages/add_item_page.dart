// ignore_for_file: unused_element

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/item.dart';
import '../services/item_service.dart';
import '../widgets/map_picker_page.dart';
import 'dart:typed_data'; // read image bytes
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/ai_matching_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'item_detail_page.dart';

class AddItemPage extends StatefulWidget {
  //  const AddItemPage({super.key, required ItemModel editing, required ItemModel });
  final ItemModel? editing;
  const AddItemPage({super.key, this.editing});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

class _AddItemPageState extends State<AddItemPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _tags = TextEditingController();
  final _locationController = TextEditingController();

  String _type = 'lost';
  String _category = 'General';
  // ignore: prefer_final_fields
  List<XFile> _photos = [];
  double? _lat, _lng;
  String _locationText = '';

  bool _saving = false;

  bool get _isEdit => widget.editing != null;

  final _cats = const [
    'General',
    'Electronics',
    'Clothing',
    'Accessories',
    'Cards',
    'Documents',
    'Keys',
    'Bags',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    final it = widget.editing;
    if (it != null) {
      _type = it.type;
      _category = it.category;
      _title.text = it.title;
      _desc.text = it.desc;
      _tags.text = it.tags.join(', ');
      _lat = it.lat;
      _lng = it.lng;
      _locationText = it.locationText;
      _locationController.text = it.locationText;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _tags.dispose();
    super.dispose();
  }

  /// AI Helper: Generates tags from an image file

  Future<void> _generateTagsFromImage(XFile file) async {
    print('!!! STARTING SMART AI SCAN !!!');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Asking AI to fill out your post...')),
    );

    try {
      final model = GenerativeModel(
        model: 'gemini-2.0-flash-lite-001',
        apiKey: dotenv.env['GEMINI_API_KEY']!,
      );

      final Uint8List imageBytes = await file.readAsBytes();

      final validCategories = _cats.join(', ');

      final prompt = TextPart(
        "Analyze this lost item image. \n"
        "Return a single JSON object with these 4 fields:\n"
        "1. 'title': A short, clear title (e.g., 'Black Leather Wallet', 'Honda Car Keys').\n"
        "2. 'description': A helpful description (max 20 words). Focus on color, brand, and distinguishing features.\n"
        "3. 'category': Pick exactly ONE from this list: [$validCategories]. If unsure, use 'General'.\n"
        "4. 'tags': A single string of 5 comma-separated keywords.\n\n"
        "IMPORTANT: Return ONLY raw JSON. Do not use Markdown blocks (```json).",
      );

      final response = await model.generateContent([
        Content.multi([prompt, DataPart('image/jpeg', imageBytes)]),
      ]);

      final String? output = response.text;
      print('Gemini JSON Response: $output');

      if (output != null && output.isNotEmpty) {
        final cleanJson = output
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        final Map<String, dynamic> data = jsonDecode(cleanJson);

        setState(() {
          // Auto fill title (only if empty)
          if (_title.text.isEmpty) {
            _title.text = data['title'] ?? '';
          }

          // Auto fill description (only if empty or short)
          if (_desc.text.length < 5) {
            _desc.text = data['description'] ?? '';
          }

          // Auto select category
          String aiCategory = data['category'] ?? 'General';
          // Ensure the AI picked a valid category from our list
          if (_cats.contains(aiCategory)) {
            _category = aiCategory;
          } else {
            _category = 'General'; // Fallback if AI makes up a category
          }

          // Auto fill Tags
          String newTags = data['tags'] ?? '';
          final currentTags = _tags.text;
          final Set<String> uniqueTags = {};
          if (currentTags.isNotEmpty) {
            uniqueTags.addAll(currentTags.split(', '));
          }
          uniqueTags.addAll(newTags.split(', ').map((e) => e.trim()));
          _tags.text = uniqueTags.join(', ');
        });
      }
    } catch (e) {
      print('Gemini Error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI Error: $e')));
    }
  }

  Future<void> _showPhotoOptions() async {
    // Check if we've already reached the limit
    if (_photos.length >= 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only add up to 4 photos')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo (Camera)'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _pickMultiImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);

    if (file != null) {
      setState(() {
        if (_photos.length < 4) {
          _photos.add(file);
        } else {
          // This is a safeguard, though the limit is already checked before
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Photo limit reached.')));
        }
      });

      await _generateTagsFromImage(file);
    }
  }

  Future<void> _pickMultiImage() async {
    final picker = ImagePicker();
    final int remainingSlots = 4 - _photos.length;

    if (remainingSlots <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only add up to 4 photos.')),
      );
      return;
    }

    final files = await picker.pickMultiImage(imageQuality: 85);

    if (files.isNotEmpty) {
      setState(() {
        int itemsToAdd = (files.length > remainingSlots)
            ? remainingSlots
            : files.length;

        _photos.addAll(files.take(itemsToAdd));

        if (files.length > itemsToAdd) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Photo limit of 4 reached. Not all images were added.',
              ),
            ),
          );
        }
      });
      if (files.isNotEmpty) {
        await _generateTagsFromImage(files.first);
      }
    }
  }

  Future<void> _pickLocation() async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerPage()),
    );
    if (res is Map && res['lat'] != null) {
      setState(() {
        _lat = res['lat'];
        _lng = res['lng'];
        _locationText = res['text'] ?? '';
        _locationController.text = res['text'] ?? '';
      });
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    if (_lat == null || _lng == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please pick a location')));
      return;
    }

    final isEdit = widget.editing != null;

    if (!isEdit && _photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one photo')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final tagList = _tags.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (!isEdit) {
        await ItemService.instance.createItem(
          type: _type,
          title: _title.text,
          desc: _desc.text,
          category: _category,
          tags: tagList,
          lat: _lat!,
          lng: _lng!,
          //          locationText: _locationText,
          locationText: _locationController.text,
          photos: _photos,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Post submitted for Admin Approval. It will appear after review.',
              ),
              duration: Duration(seconds: 3),
            ),
          );

          // A. Get Candidates
          final candidates = await ItemService.instance.getMatchingCandidates(
            currentType: _type,
            category: _category,
          );

          print(
            "🔍 DEBUG: Found ${candidates.length} candidates in the database.",
          );

          if (candidates.isNotEmpty) {
            Uint8List imageBytes = Uint8List(0);
            if (_photos.isNotEmpty) {
              imageBytes = await _photos.first.readAsBytes();
            }
            final tempItem = ItemModel(
              id: 'temp',
              type: _type,
              title: _title.text,
              desc: _desc.text,
              category: _category,
              tags: tagList,
              ownerUid: '',
              postedAt: Timestamp.now(),
              locationText: '',
              photos: [],
              lat: 0,
              lng: 0,
              status: '', // Provide an appropriate status value here
            );

            // B. Call AI
            final matches = await AiMatchingService.instance.findMatches(
              newItem: tempItem,
              imageBytes: imageBytes,
              candidates: candidates,
            );

            if (matches.isNotEmpty && mounted) {
              _showMatchDialog(matches, candidates);
              // Don't pop yet if we are showing dialog
              setState(() => _saving = false);
              return;
            }
          }
        }
      } else {
        // UPDATE (keep existing photos in this simple edit mode)
        await ItemService.instance.updateItem(widget.editing!.id, {
          'type': _type,
          'title': _title.text.trim(),
          'desc': _desc.text.trim(),
          'category': _category,
          'tags': tagList,
          'lat': _lat,
          'lng': _lng,
          'locationText': _locationText,
          'updatedAt': DateTime.now(), // optional
        });
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved')));
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMatchDialog(
    List<Map<String, dynamic>> matches,
    List<ItemModel> allCandidates,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 Possible Matches Found!'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: matches.length,
            itemBuilder: (ctx, i) {
              final match = matches[i];
              // Find the full item object
              final fullItem = allCandidates.firstWhere(
                (c) => c.id == match['id'],
                orElse: () => allCandidates.first, // Safety fallback
              );

              return Card(
                color: Colors.green[50],
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Text(
                      '${match['score']}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    fullItem.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(match['reason'] ?? 'Visual match detected.'),
                  onTap: () {
                    // Optional: Navigate to detail page
                    //Navigator.pop(ctx); // Close dialog
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ItemDetailPage(item: fullItem),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close Add Page
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String? _vTitle(String? v) =>
      (v == null || v.trim().length < 3) ? 'Enter title (min 3 chars)' : null;
  String? _vDesc(String? v) => (v == null || v.trim().length < 10)
      ? 'Enter description (min 10 chars)'
      : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit post' : 'Create post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'lost', child: Text('Lost')),
                  DropdownMenuItem(value: 'found', child: Text('Found')),
                ],
                onChanged: (v) => setState(() => _type = v as String),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: _vTitle,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: _vDesc,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: _cats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v as String),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _photos.length; i++)
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_photos[i].path),
                            height: 80,
                            width: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // -- This is the Remove Button ---
                        InkWell(
                          onTap: () {
                            setState(() {
                              _photos.removeAt(i);
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),

                  if (_photos.length < 4)
                    InkWell(
                      onTap: _showPhotoOptions,
                      child: Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          border: Border.all(),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_a_photo_outlined),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              /*              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _locationText.isEmpty ? 'Pick location' : _locationText,
                ),
                leading: const Icon(Icons.place_outlined),
                trailing: ElevatedButton(
                  onPressed: _pickLocation,
                  child: const Text('map'),
                ),
              ), */
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location',
                        hintText: 'e.g. Library Level 2',
                        prefixIcon: Icon(Icons.place_outlined),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      // Simple validation to ensure they didn't leave it blank
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Plesae pick or type a location'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // The Map Button
                  Container(
                    height: 56,
                    margin: const EdgeInsets.only(top: 0),
                    child: ElevatedButton(
                      onPressed: _pickLocation,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Icon(Icons.map),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const CircularProgressIndicator()
                      : Text(_isEdit ? 'Save' : 'Post'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
