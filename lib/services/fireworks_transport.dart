import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:genui/genui.dart';
import 'package:http/http.dart' as http;

// Secrets are read at runtime from .env (loaded in main via flutter_dotenv),
// with --dart-define as a compile-time override. No key is baked into source;
// the app refuses to run until a key is supplied (see the StateError below).
String get _apiKey {
  const defined = String.fromEnvironment('FIREWORKS_API_KEY');
  if (defined.isNotEmpty) return defined;
  return dotenv.maybeGet('FIREWORKS_API_KEY') ?? '';
}

String get _model {
  const defined = String.fromEnvironment('FIREWORKS_MODEL');
  if (defined.isNotEmpty) return defined;
  // Default model. Must be one deployed on your Fireworks account — a model
  // id that 404s means it isn't deployed/subscribed there. deepseek-v4-pro is
  // known to work on this account; with the trimmed catalog it's faster than
  // the original 77KB-prompt run. For a faster model, deploy one on Fireworks
  // and set FIREWORKS_MODEL (e.g. a small instruct model you have access to).
  return dotenv.maybeGet('FIREWORKS_MODEL') ??
      'accounts/fireworks/models/deepseek-v4-pro';
}

// Vision model used when a turn carries a camera image. If the default 404s on
// your account, set FIREWORKS_VISION_MODEL in .env to the router alias
// fireworks/glm-4p5v or fireworks/qwen3-vl-32b-instruct.
String get _visionModel {
  const defined = String.fromEnvironment('FIREWORKS_VISION_MODEL');
  if (defined.isNotEmpty) return defined;
  return dotenv.maybeGet('FIREWORKS_VISION_MODEL') ??
      'accounts/fireworks/models/glm-4p5v';
}

const _baseUrl = 'https://api.fireworks.ai/inference/v1/chat/completions';

// Low temperature for deterministic A2UI JSON structure — high creativity
// breaks the parser's structural constraints.
const _temperature = 0.1;

// Hard ceilings so a stalled stream can never hang the UI forever.
const _connectTimeout = Duration(seconds: 30);
const _streamTimeout = Duration(seconds: 60);

const _logTag = '[Guardian/Fireworks]';

void _log(Object? message) => debugPrint('$_logTag $message');

/// Captures one request/response cycle with Fireworks so the UI can show
/// exactly what was sent and what came back (live, while streaming, and in the
/// error view after a failure) instead of a generic "no interface" message.
class FireworksTrace {
  /// The user's prompt text (including the appended tools context).
  String userPrompt = '';

  /// The full JSON request body sent to Fireworks.
  String requestBody = '';

  /// HTTP status code received (0 if the request failed before a response).
  int statusCode = 0;

  /// Human-readable status line, e.g. "200 OK" or "401 Unauthorized".
  String statusLine = '';

  /// Raw model content assembled from streamed delta chunks.
  String content = '';

  /// Notable stream events (skipped lines, parse warnings, [DONE], errors),
  /// appended as they happen — useful when content is empty or malformed.
  final ValueNotifier<String> liveLog = ValueNotifier('');

  /// Live-updating view of [content] so the UI can render it as it streams.
  final ValueNotifier<String> liveContent = ValueNotifier('');

  /// The error that terminated the cycle, if any (toString'd for display).
  String error = '';

  /// True once the cycle has finished (success or failure).
  bool finished = false;

  void reset() {
    userPrompt = '';
    requestBody = '';
    statusCode = 0;
    statusLine = '';
    content = '';
    error = '';
    finished = false;
    liveLog.value = '';
    liveContent.value = '';
  }

  void appendLog(String line) {
    final cur = liveLog.value;
    liveLog.value = cur.isEmpty ? line : '$cur\n$line';
  }

  void dispose() {
    liveLog.dispose();
    liveContent.dispose();
  }
}

/// Builds a [Conversation] wired to Fireworks AI with streaming.
///
/// Observability: every stage of the request (build, send, status, each chunk,
/// parse failures, completion, errors) is logged with the `$_logTag` prefix so
/// it shows up in `flutter run` console output, and mirrored into [trace] for
/// on-screen display.
Conversation buildConversation({
  required SurfaceController controller,
  required String systemPrompt,
  required FireworksTrace trace,
}) {
  late A2uiTransportAdapter transport;
  // content can be a String (text turns) or a List (image turns), so the value
  // type is Object.
  final List<Map<String, Object>> history = [];

  transport = A2uiTransportAdapter(
    onSend: (ChatMessage message) async {
      trace.reset();
      // A user turn can be: plain text (voice/scenario), a UI interaction (the
      // driver tapped a Button / submitted a ChoicePicker), or a camera image.
      // Interaction data lives in a UiInteractionPart and images in an image
      // DataPart — neither is text, so the old getText() returned '' and the
      // conversation was one-way. _contentFromMessage serializes every part:
      // it returns a String for text-only turns, or an OpenAI-style content
      // array ([{type:text,…},{type:image_url,…}]) when an image is present.
      // When an image is present we also route to a vision-capable model.
      final content = _contentFromMessage(message);
      final hasImage = content is List;
      final model = hasImage ? _visionModel : _model;
      final contentPreview = content is String
          ? content.substring(0, content.length.clamp(0, 80))
          : '[image + text]';
      trace.userPrompt = content is String ? content : contentPreview;
      _log('send → model=$model hasImage=$hasImage prompt="$contentPreview" '
          'history=${history.length} apiKey=${_apiKey.isEmpty ? "<MISSING>" : "set(${_apiKey.length} chars)"}');
      trace.appendLog('send → model=$model${hasImage ? ' (vision)' : ''}');

      // Fail fast with an actionable message instead of a silent 401 hang.
      if (_apiKey.isEmpty) {
        _log('ERROR: FIREWORKS_API_KEY is empty. Pass it via '
            '--dart-define=FIREWORKS_API_KEY=... or the FIREWORKS_API_KEY env var.');
        trace.error = 'FIREWORKS_API_KEY is not configured.';
        throw StateError(
          'FIREWORKS_API_KEY is not configured. Run with '
          '--dart-define=FIREWORKS_API_KEY=YOUR_KEY '
          '(flutter run --dart-define=FIREWORKS_API_KEY=YOUR_KEY).',
        );
      }

      history.add({'role': 'user', 'content': content});

      // Live camera mode sends a new image every few seconds. Keeping every
      // prior image in history would balloon the context (and cost), so when
      // this turn carries an image, replace earlier image turns with a short
      // text placeholder — only the latest frame stays as an image.
      if (hasImage) {
        for (var i = 0; i < history.length - 1; i++) {
          if (history[i]['content'] is List) {
            history[i] = {
              'role': history[i]['role'] as String,
              'content': '[earlier camera frame]',
            };
          }
        }
      }

      final client = http.Client();
      try {
        final request = http.Request('POST', Uri.parse(_baseUrl));
        request.headers['Authorization'] = 'Bearer $_apiKey';
        request.headers['Content-Type'] = 'application/json';
        request.headers['Accept'] = 'text/event-stream';

        final bodyMap = {
          'model': model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...history,
          ],
          'max_tokens': 16384,
          'top_k': 40,
          'presence_penalty': 0,
          'frequency_penalty': 0,
          'temperature': _temperature,
          'stream': true,
          // NOTE: this endpoint rejects non-standard fields (HTTP 400
          // "Extra inputs are not permitted"), so GLM-5.x thinking cannot be
          // disabled via chat_template_kwargs here. For instant output, use a
          // non-reasoning model (see _model default / FIREWORKS_MODEL env).
        };
        request.body = jsonEncode(bodyMap);
        // Pretty-printed copy for human reading in the UI. The system prompt is
        // long so it's truncated; image data URLs are enormous so they're
        // stripped to a placeholder (via _traceMessage) to keep it readable.
        final traceMessages = <Map<String, Object>>[
          {
            'role': 'system',
            'content':
                '${systemPrompt.substring(0, systemPrompt.length.clamp(0, 200))}… (${systemPrompt.length} chars total)',
          },
          ...history.map(_traceMessage),
        ];
        trace.requestBody = const JsonEncoder.withIndent('  ').convert({
          'model': model,
          'messages': traceMessages,
          'max_tokens': 16384,
          'temperature': _temperature,
          'stream': true,
        });

        _log('request → POST $_baseUrl (body ${request.body.length} bytes)');

        final response = await client.send(request).timeout(
          _connectTimeout,
          onTimeout: () => throw TimeoutException(
            'Fireworks connect timed out after ${_connectTimeout.inSeconds}s',
            _connectTimeout,
          ),
        );
        trace.statusCode = response.statusCode;
        trace.statusLine =
            '${response.statusCode} ${response.reasonPhrase ?? ""}'.trim();
        _log('response ← status=${response.statusCode} '
            'content-type=${response.headers['content-type']}');
        trace.appendLog('response ← ${trace.statusLine}');

        // Non-2xx: read the body once, log it, and surface a clear error.
        // This is the path that previously caused infinite loading (401 with
        // a JSON error body that produced no SSE `data:` lines).
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final body = await response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .join('\n');
          _log('ERROR: HTTP ${response.statusCode} body:\n$body');
          trace.content = body;
          trace.liveContent.value = body;
          trace.appendLog('ERROR: HTTP ${response.statusCode}\n$body');
          trace.error =
              'Fireworks returned HTTP ${response.statusCode}. ${_summarizeErrorBody(body)}';
          throw http.ClientException(trace.error, Uri.parse(_baseUrl));
        }

        final StringBuffer fullContent = StringBuffer();
        var chunkCount = 0;
        var sawDone = false;

        await for (final chunk in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(_streamTimeout)) {
          if (chunk.isEmpty) continue;
          if (!chunk.startsWith('data: ')) {
            // Some providers send keep-alive comments or error lines mid-stream.
            if (!chunk.startsWith(':')) {
              final preview =
                  chunk.substring(0, chunk.length.clamp(0, 120));
              _log('skip (non-data line): $preview');
              trace.appendLog('skip: $preview');
            }
            continue;
          }
          final data = chunk.substring(6).trim();
          if (data == '[DONE]') {
            sawDone = true;
            _log('stream ← [DONE]');
            trace.appendLog('stream ← [DONE]');
            break;
          }

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            // Surface provider-side errors carried inside an otherwise-200 stream.
            if (json['error'] != null) {
              final err = json['error'];
              final msg = err is Map ? err['message'] ?? err : err;
              _log('ERROR: stream error payload: $msg');
              trace.appendLog('ERROR: stream error: $msg');
              trace.error = 'Fireworks stream error: $msg';
              throw http.ClientException(trace.error);
            }
            final delta = json['choices']?[0]?['delta']?['content'] as String?;
            // Reasoning models (GLM-5.x / Qwen3) stream chain-of-thought in a
            // separate `reasoning_content` field. We must NOT feed it to the
            // A2UI parser (it isn't JSON) — but we surface it in the trace so a
            // slow turn is diagnosable instead of looking like a frozen UI.
            final reasoning =
                json['choices']?[0]?['delta']?['reasoning_content'] as String?;
            if (reasoning != null && reasoning.isNotEmpty) {
              trace.appendLog('thinking… (${reasoning.length} chars)');
            }
            if (delta != null && delta.isNotEmpty) {
              fullContent.write(delta);
              trace.content = fullContent.toString();
              trace.liveContent.value = trace.content;
              transport.addChunk(delta);
              chunkCount++;
            }
          } catch (e) {
            // Don't swallow parse failures silently — log them so a malformed
            // stream is diagnosable instead of looking like an infinite hang.
            if (e is http.ClientException) rethrow;
            final preview =
                data.substring(0, data.length.clamp(0, 120));
            _log('warn: failed to parse SSE data line: $e → "$preview"');
            trace.appendLog('warn: parse failed: $e → "$preview"');
          }
        }

        // The A2UI parse pipeline is asynchronous: addChunk() feeds an
        // async StreamController chain (transformer → asBroadcastStream →
        // _messageStream → controller.handleMessage → registry → conversation
        // events), so each parsed A2UI message reaches the HUD only after a
        // string of microtask hops. When Fireworks ships the final content
        // chunk and the `data: [DONE]` sentinel in the same SSE frame (the
        // common case), the await-for loop above exits BEFORE those microtasks
        // drain — the surface-update event hasn't fired yet, so the HUD's
        // safety-net wrongly reports "no renderable interface" for output that
        // is in fact valid. A zero-delay Timer resumes only after the microtask
        // queue is fully drained, guaranteeing every parsed message has been
        // delivered to the controller before sendRequest() returns.
        await Future.delayed(Duration.zero);

        history.add({'role': 'assistant', 'content': fullContent.toString()});

        _log('done ← chunks=$chunkCount done=$sawDone length=${fullContent.length}');
        trace.appendLog('done ← chunks=$chunkCount length=${fullContent.length}');

        // Empty response with no error: the model returned nothing useful.
        // Surface it instead of leaving the UI spinning forever.
        if (fullContent.isEmpty) {
          _log('ERROR: empty response (no content chunks). '
              'The model returned no GenUI output.');
          trace.error = 'Empty response — the model produced no output.';
          throw StateError(
            'Fireworks returned an empty response. The model produced no '
            'GenUI output — check the system prompt and model id "$_model".',
          );
        }

        _log('response content:\n${fullContent.toString()}');
      } on http.ClientException catch (e) {
        trace.error = e.toString();
        rethrow;
      } on StateError catch (e) {
        trace.error = e.toString();
        rethrow;
      } on TimeoutException catch (e) {
        trace.error = e.toString();
        rethrow;
      } catch (e, st) {
        _log('ERROR: unexpected exception: $e\n$st');
        trace.error = e.toString();
        rethrow;
      } finally {
        trace.finished = true;
        client.close();
      }
    },
  );

  // Debug taps to pinpoint where the A2UI pipeline breaks.
  transport.incomingMessages.listen(
    (m) {
      _log('parsed A2UI message → ${m.runtimeType}');
      trace.appendLog('parsed → ${m.runtimeType}');
    },
    onError: (e, st) {
      _log('parsed A2UI stream ERROR: $e\n$st');
      trace.appendLog('parse stream ERROR: $e');
    },
  );
  controller.surfaceUpdates.listen(
    (u) {
      _log('surfaceUpdate → ${u.runtimeType}');
      trace.appendLog('surfaceUpdate → ${u.runtimeType}');
    },
    onError: (e, st) {
      _log('surfaceUpdates ERROR: $e\n$st');
      trace.appendLog('surfaceUpdate ERROR: $e');
    },
  );

  return Conversation(controller: controller, transport: transport);
}

/// Pulls a short human-readable reason out of a Fireworks error JSON body.
String _summarizeErrorBody(String body) {
  if (body.isEmpty) return 'Empty response body.';
  try {
    final json = jsonDecode(body);
    final err = json is Map ? json['error'] : null;
    if (err is Map) {
      return (err['message'] ?? err['description'] ?? err).toString();
    }
    if (err != null) return err.toString();
    if (json is Map && json['message'] != null) return json['message'].toString();
  } catch (_) {
    /* fall through to raw trim */
  }
  final trimmed = body.trim();
  return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
}

/// Serializes a [ChatMessage] into the `content` sent to Fireworks.
///
/// Returns a [String] for text-only turns (kept as a plain string so the text
/// model path is unchanged), or an OpenAI-style content array
/// `[{type:text,…},{type:image_url,image_url:{url:"data:image/jpeg;base64,…"}}]`
/// when the message carries a camera image — which also routes the call to a
/// vision model (see `onSend`).
///
/// Text turns come through as [TextPart]s; interactive turns (a Button press,
/// a ChoicePicker submission) come through as a [DataPart] with the A2UI
/// interaction MIME type, whose payload is `{"version":"v0.9","action":{…}}`.
/// We surface the action as a `[USER_ACTION] …` line so the model can continue
/// the dialog — the system prompt instructs it to treat these as the driver's
/// reply and generate the next surface.
Object _contentFromMessage(ChatMessage message) {
  final textBuf = StringBuffer();
  String? imageDataUrl;
  for (final part in message.parts) {
    if (part is TextPart) {
      if (part.text.isEmpty) continue;
      if (textBuf.isNotEmpty) textBuf.write('\n');
      textBuf.write(part.text);
    } else if (part is DataPart &&
        part.mimeType.startsWith('image/')) {
      imageDataUrl =
          'data:${part.mimeType};base64,${base64Encode(part.bytes)}';
    } else if (part is DataPart &&
        part.mimeType == UiPartConstants.interactionMimeType) {
      final interaction = UiInteractionPart.fromDataPart(part).interaction;
      String actionLine;
      try {
        final decoded = jsonDecode(interaction) as Map<String, dynamic>;
        final action = decoded['action'] ?? decoded;
        actionLine = '[USER_ACTION] ${jsonEncode(action)}';
      } catch (_) {
        actionLine = '[USER_ACTION] $interaction';
      }
      if (textBuf.isNotEmpty) textBuf.write('\n');
      textBuf.write(actionLine);
    }
  }

  final text = textBuf.toString();
  if (imageDataUrl == null) return text;

  // Multimodal content: text first (if any), then the image.
  final content = <Map<String, Object>>[];
  if (text.isNotEmpty) content.add({'type': 'text', 'text': text});
  content.add({
    'type': 'image_url',
    'image_url': {'url': imageDataUrl},
  });
  return content;
}

/// Builds a trace-friendly copy of a history entry: identical for text turns,
/// but with image data URLs replaced by a `[image: N bytes]` placeholder so the
/// on-screen request dump isn't swamped by megabytes of base64.
Map<String, Object> _traceMessage(Map<String, Object> entry) {
  final content = entry['content'];
  if (content is! List) return entry;
  final stripped = <Map<String, Object>>[];
  for (final raw in content) {
    if (raw is Map && raw['type'] == 'image_url') {
      final imageUrl = raw['image_url'];
      String preview = '[image]';
      if (imageUrl is Map) {
        final url = imageUrl['url'];
        if (url is String && url.startsWith('data:')) {
          final comma = url.indexOf(',');
          final b64 = comma >= 0 ? url.substring(comma + 1) : '';
          preview = '[image: ${(b64.length * 3 / 4).round()} bytes]';
        }
      }
      stripped.add({
        'type': 'image_url',
        'image_url': {'url': preview},
      });
    } else if (raw is Map) {
      stripped.add(Map<String, Object>.from(raw));
    }
  }
  return {'role': entry['role'] as String, 'content': stripped};
}
