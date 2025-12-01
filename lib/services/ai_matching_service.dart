import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/item.dart';

class AiMatchingService {
  static final AiMatchingService instance = AiMatchingService._init();
  AiMatchingService._init();

  Future<List<Map<String, dynamic>>> findMatches({
    required ItemModel newItem,
    required Uint8List imageBytes, // The image user just picked
    required List<ItemModel> candidates,
  }) async {
    if (candidates.isEmpty) return [];

    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print("❌ AI Error: GEMINI_API_KEY is missing in .env file!");
      return [];
    }

    try {
      // Setup the Model
      final model = GenerativeModel(
        model: 'gemini-2.0-flash-lite-001',
        apiKey: apiKey,
      );

      // Prepare the Candidates List as a String
      // We send the Ai the text of the candidates, but the image of the new item.
      String candidateListString = candidates
          .map((item) {
            return "ID: ${item.id} | Title: ${item.title} | Description: ${item.desc} | Tags: ${item.tags.join(', ')}";
          })
          .join('\n');

      // The prompt
      final promptText =
          """
      Act as a matching engine.
      
      INPUT ITEM:
      Title: ${newItem.title}
      Desc: ${newItem.desc}

      CANDIDATE DATABASE:
      $candidateListString

      TASK:
      Compare the INPUT agains EVERY SINGLE ITEM in the CANDIDATE DATABASE.

      CRITICAL RULES:
      1. Do Not stop at the first match. Check every candidate.
      2. Return ALL matches with a score > 60.
      3. If there are 3 matches, return 3 items in the list. If none, return an empty list.
      
      OUTPUT FORMAT:
      Return ONLY a JSON List. Do not write "Here is the JSON" or use markdown blocks.
      Example: [{"id": "123", "score": 90, "reason": "Visual match"}]
      """;

      // Send Request
      final content = [
        Content.multi([
          TextPart(promptText),
          //If we have an image, send it. If not, just text (less accurate but works)
          if (imageBytes != null) DataPart('image/jpeg', imageBytes),
        ]),
      ];

      final response = await model.generateContent(content);
      final output = response.text;

      print("AI Match Response: $output"); // Debugging

      if (output != null) {
        // Clean the response
        final startIndex = output.indexOf('[');
        final endIndex = output.lastIndexOf(']');

        if (startIndex != -1 && endIndex != -1) {
          final cleanJson = output.substring(startIndex, endIndex + 1);

          final List<dynamic> jsonList = jsonDecode(cleanJson);
          return jsonList.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (e) {
      print("AI Matching Error: $e");
    }
    return [];
  }
}
