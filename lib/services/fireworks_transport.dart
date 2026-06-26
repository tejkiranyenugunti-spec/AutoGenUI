import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;

// Set via --dart-define=FIREWORKS_API_KEY=your_key or env
const _apiKey = String.fromEnvironment('FIREWORKS_API_KEY', defaultValue: '');
const _model = 'accounts/fireworks/models/glm-5p2';
const _baseUrl = 'https://api.fireworks.ai/inference/v1/chat/completions';

/// Builds a [Conversation] wired to Fireworks AI with streaming.
Conversation buildConversation({
  required SurfaceController controller,
  required String systemPrompt,
}) {
  late A2uiTransportAdapter transport;
  final List<Map<String, String>> history = [];

  transport = A2uiTransportAdapter(
    onSend: (ChatMessage message) async {
      // Add user turn to history
      history.add({
        'role': 'user',
        'content': message.getText() ?? '',
      });

      final client = http.Client();
      try {
        final request = http.Request('POST', Uri.parse(_baseUrl));
        request.headers['Authorization'] = 'Bearer $_apiKey';
        request.headers['Content-Type'] = 'application/json';
        request.headers['Accept'] = 'text/event-stream';

        request.body = jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...history,
          ],
          'max_tokens': 4096,
          'top_k': 40,
          'presence_penalty': 0,
          'frequency_penalty': 0,
          'temperature': 0.3,
          'stream': true,
        });

        final response = await client.send(request);
        debugPrint('Fireworks status: ${response.statusCode}');

        final StringBuffer fullContent = StringBuffer();

        await for (final chunk in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!chunk.startsWith('data: ')) continue;
          final data = chunk.substring(6).trim();
          if (data == '[DONE]') break;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final delta = json['choices']?[0]?['delta']?['content'] as String?;
            if (delta != null && delta.isNotEmpty) {
              fullContent.write(delta);
              transport.addChunk(delta);
            }
          } catch (_) {}
        }

        // Add assistant turn to history
        history.add({
          'role': 'assistant',
          'content': fullContent.toString(),
        });

        debugPrint('Fireworks response length: ${fullContent.length}');
      } catch (e) {
        debugPrint('Fireworks error: $e');
        rethrow;
      } finally {
        client.close();
      }
    },
  );

  return Conversation(controller: controller, transport: transport);
}

extension on ChatMessage {
  String? getText() {
    if (parts.isEmpty) return null;
    final part = parts.first;
    if (part is TextPart) return part.text;
    return null;
  }
}
