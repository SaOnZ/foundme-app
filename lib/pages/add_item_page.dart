// ignore_for_file: unused_element

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // read image bytes
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/item.dart';
import '../services/item_service.dart';
import '../widgets/map_picker_page.dart';
import '../services/ai_matching_service.dart';
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
  String _category = 'Others';
  List<XFile> _photos = [];
  double? _lat, _lng;
  String _locationText = '';

  bool _saving = false;
  bool _isAiScanning = false;

  bool get _isEdit => widget.editing != null;

  final _cats = const [
    'Electronics',
    'Wallets & IDs',
    'Keys',
    'Bags & Luggage',
    'Clothing & Wearables',
    'Books & Stationery',
    'Water Bottles',
    'Sports & Hobby',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    final it = widget.editing;
    if (it != null) {
      _type = it.type.toLowerCase();
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Colors.blueAccent,
              size: 28,
            ),
            SizedBox(width: 10),
            Text("Attention"),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateTagsFromImage(XFile file) async {
    setState(() => _isAiScanning = true);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.white),
            SizedBox(width: 10),
            Text('AI is analyzing your image...'),
          ],
        ),
        backgroundColor: Colors.purple,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final Uint8List imageBytes = await file.readAsBytes();

      final result = await FirebaseFunctions.instance
          .httpsCallable('analyzeItemImage')
          .call({
            'imageBase64': base64Encode(imageBytes),
            'validCategories': _cats,
          });

      final data = result.data;
      if (data is Map) {
        final parsed = Map<String, dynamic>.from(data);

        setState(() {
          if (_title.text.isEmpty) {
            _title.text = parsed['title'] ?? '';
          }
          if (_desc.text.length < 5) {
            _desc.text = parsed['description'] ?? '';
          }

          final String aiCategory = parsed['category'] ?? 'Others';
          _category = _cats.contains(aiCategory) ? aiCategory : 'Others';

          final String newTags = parsed['tags'] ?? '';
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
    } finally {
      setState(() => _isAiScanning = false);
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
      _showErrorDialog('Please pick a location using the map button.');
      return;
    }

    final isEdit = widget.editing != null;
    if (!isEdit && _photos.isEmpty) {
      _showErrorDialog(
        'Please add at least one photo to help others identify the item.',
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
        final newItemId = await ItemService.instance.createItem(
          type: _type,
          title: _title.text,
          desc: _desc.text,
          category: _category,
          tags: tagList,
          lat: _lat!,
          lng: _lng!,
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

          // Ask the findMatchingItems Cloud Function to compare this post
          // against active opposite-type items and return likely matches.
          Uint8List imageBytes = Uint8List(0);
          if (_photos.isNotEmpty) {
            imageBytes = await _photos.first.readAsBytes();
          }

          final matches = await AiMatchingService.instance.findMatches(
            itemId: newItemId,
            imageBytes: imageBytes,
          );

          if (matches.isNotEmpty && mounted) {
            // Pull the full item docs for the matched ids so the dialog can
            // show titles and let the user open them.
            final matchIds = matches
                .map((m) => m['id'])
                .whereType<String>()
                .toList();
            List<ItemModel> matchedItems = [];
            if (matchIds.isNotEmpty) {
              final snap = await FirebaseFirestore.instance
                  .collection('items')
                  .where(FieldPath.documentId, whereIn: matchIds)
                  .get();
              matchedItems = snap.docs.map(ItemModel.fromDoc).toList();
            }

            if (mounted && matchedItems.isNotEmpty) {
              _showMatchDialog(matches, matchedItems);
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
      if (mounted) _showErrorDialog('Error: $e');
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

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }

  Widget _buildToggleButton(String type, Color color) {
    final isSelected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [const BoxShadow(color: Colors.black12, blurRadius: 4)]
                : [],
          ),
          child: Text(
            type.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isSelected ? color : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit post' : 'New Report'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _buildToggleButton('lost', Colors.redAccent),
                    _buildToggleButton('found', Colors.green),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                "Photos",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ..._photos.asMap().entries.map((entry) {
                    final index = entry.key;
                    final photo = entry.value;
                    return Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(photo.path),
                            height: 100,
                            width: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(() => _photos.removeAt(index)),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),

                  if (_photos.length < 4)
                    InkWell(
                      onTap: _showPhotoOptions,
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.shade400,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: _isAiScanning
                            ? const Center(child: CircularProgressIndicator())
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    color: Colors.blueAccent,
                                  ),
                                  Text(
                                    "Add",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
              if (_isAiScanning)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    "✨ AI is analyzing image...",
                    style: TextStyle(color: Colors.purple, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _title,
                decoration: _inputDecoration('Item Title', Icons.title),
                validator: _vTitle,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _category,
                decoration: _inputDecoration(
                  'Category',
                  Icons.category_outlined,
                ),
                items: _cats
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v as String),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _desc,
                maxLines: 3,
                decoration: _inputDecoration(
                  'Description',
                  Icons.description_outlined,
                ),
                validator: _vDesc,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _tags,
                decoration: _inputDecoration(
                  'Tags (e.g. Blue, Wallet)',
                  Icons.tag,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _locationController,
                      decoration: _inputDecoration(
                        'Location (e.g. Library)',
                        Icons.place_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _pickLocation,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Colors.blue.shade50,
                        foregroundColor: Colors.blue,
                        elevation: 0,
                      ),
                      child: const Icon(Icons.map, size: 28),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _type == 'lost'
                        ? Colors.redAccent
                        : Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEdit ? 'Save Changes' : ' Submit Post',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
