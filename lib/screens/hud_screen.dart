import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:genui/genui.dart';

import '../services/camera_service.dart';
import '../services/fireworks_transport.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../widgets/normal_hud.dart';

enum HudState { normal, active, camera }

// ---------------------------------------------------------------------------
// System prompt — generic generative-UI instructions (no domain hardcoding).
// ---------------------------------------------------------------------------
const _systemPrompt = '''
You are a generative UI engine. You receive a request and render it as a live, interactive interface using the A2UI protocol — not prose.

The framework supplies the full A2UI component schema and message protocol: createSurface + updateComponents, fenced ```json blocks, a unique surfaceId per response, a root component, and each component's required properties. Use it directly. Output ONLY A2UI messages — no plan, no reasoning, no preamble, no restating the input. Generate the surface immediately.

SURFACE STRUCTURE — build a RICH, filled surface. EVERY surface follows this template:
- 2–4 GUIDANCE components: several Cards that deliver the context/instructions. A Card holds SEVERAL related items (Icon + h3 title + body text), packed into a multi-item Column — dense content blocks. Lay out two Cards SIDE BY SIDE in a Row (each `{"weight":1}`); use a second Row for the next pair, or a full-width Card for a longer block. Fill the surface — do not leave it sparse.
- exactly 1 INTERACTION component: a ChoicePicker (pick a path), a TextField (free text), or a primary Button (confirm / advance / call). Never just static text and stop; never more than one interactive control.
- Do NOT produce a tall stack of many full-width single-line rows. Use 2-up Card Rows + one interaction.

VISUAL DESIGN — build a real, varied, interactive interface, never a word dump and never a flat list of full-width rows.
- Do NOT stretch every component full-width. Put blocks SIDE BY SIDE: a Row whose children each set `"weight": 1` share the width equally (e.g. two Cards in a Row, each `{"weight":1}`). This is the default way to lay out two guidance cards.
- CRITICAL: NEVER set `align: "stretch"` on a Row. The surface scrolls vertically, so a Row has unbounded height; cross-axis stretch then forces infinite height and crashes the layout. Use `align: "start"` or `"center"` on Rows. (Column `align: "stretch"` is fine — that stretches width, which is bounded.)
- GROUP content into Cards. A Card holds SEVERAL related items (Icon + h3 title + body text), packed with a multi-item Column — not one lonely line per card.
- Use a DIVERSE mix of components across the surface — never just a stack of Text. Reach for Icon (visual cues), ChoicePicker (selection), Button (actions), TextField (input), Divider (sections), Slider / CheckBox / List where they fit the data. Match the component to the data shape.
- LAYOUT: use Row/Column with justify ("center","spaceBetween","start") and align ("center","start"). Put an Icon BESIDE a headline in a Row. Put the interaction control in its own Row/area, not stretched into a giant empty row.
- HIERARCHY with Text variants: one h1 headline (with an Icon beside it), h2 section headers, h3 item titles, caption notes, short body lines. Keep each Text concise (~6 words).
- Make the single most important action a "primary" Button; secondary actions "borderless" Buttons.
- AESTHETIC: native macOS dark — system-blue (#0A84FF) accent, translucent rounded cards (10px), hairline 0.5px separators, SF-style tight typography, soft flat surfaces, no glow/neon. Buttons ~44px / 8px radius; ChoicePicker as uniform flat segmented pills (7px radius, 2–5 short options, no checkmarks).
- Avoid empty space: do not place one short Text alone in a full-width stretch row. Either group it into a Card with siblings, put it in a Row with an Icon, or put it beside another block via a weighted Row.

INTERACTIVITY — use inputs only when you genuinely need info that changes the response.
- Ask one question at a time. ChoicePicker for fixed options, TextField for free text. Give the input a data path and bind that SAME path in the submit button:
  - ChoicePicker: {"id":"picker","component":"ChoicePicker","path":"answer","displayStyle":"chips","variant":"mutuallyExclusive","options":[{"value":"yes","label":"Yes"},{"value":"no","label":"No"}]}
  - TextField:   {"id":"inp","component":"TextField","variant":"shortText","value":{"path":"answer"},"label":"Your answer"}
  - Submit Button: {"id":"submit","component":"Button","child":"submitText","variant":"primary","action":{"event":{"name":"answer_submitted","context":{"answer":{"path":"answer"}}}}}  — the context MUST bind the exact same path as the input.
- ALWAYS set "sendDataModel": true on createSurface when you render ANY input. Without it the input's value is never stored, the button context resolves empty, and you will receive a blank answer.
- On `[USER_ACTION] {"name":"...","context":{...}}`, the context already holds the user's answer — USE IT, do not re-ask. Generate the NEXT surface.
- A ChoicePicker with "variant":"multipleSelection" works as a mark-each-step-done checklist.

CORRECTNESS (the parser rejects unknown fields):
- Every Button MUST reference a SEPARATE Text child by id, e.g. {"id":"btn1","component":"Button","child":"btn1text","variant":"primary","action":{"event":{"name":"done"}}} plus {"id":"btn1text","component":"Text","text":"Done"}.
- Card takes a single "child" (an id), NOT "children".
- One component MUST have id "root". Every id referenced in any children/child MUST exist as its own component in the same updateComponents array.
- Use "variant" for Text style, never "hint".
''';

// ---------------------------------------------------------------------------
// Demo scenarios with metadata
// ---------------------------------------------------------------------------
class _Scenario {
  final String icon;
  final String label;
  final String prompt;
  final String category;
  const _Scenario(this.icon, this.label, this.prompt, this.category);
}

const _scenarios = [
  _Scenario('🫀', 'Heart Attack', 'I think I\'m having a heart attack', 'Medical'),
  _Scenario('💨', 'Tire Blowout\n(with spare)', 'My tire just blew out, I have a spare tire and jack', 'Vehicle'),
  _Scenario('🔧', 'Tire Blowout\n(no spare)', 'My tire blew out and I have no spare tire', 'Vehicle'),
  _Scenario('🚘', 'Being Followed', 'Someone is following me and I\'m scared', 'Safety'),
  _Scenario('🌊', 'Flooded Road', 'The road ahead is completely flooded', 'Road'),
  _Scenario('💨', 'Engine Failure', 'My engine is making a horrible knocking noise and smoking', 'Vehicle'),
  _Scenario('⚡', 'Battery Dead', 'My car battery is dead, I have jumper cables', 'Vehicle'),
  _Scenario('🦺', 'Accident', 'I just got into a car accident', 'Safety'),
];

// ---------------------------------------------------------------------------
// Tools that user can configure
// ---------------------------------------------------------------------------
const _allTools = [
  ('🔧', 'Spare Tire'),
  ('🔩', 'Car Jack'),
  ('🔑', 'Lug Wrench'),
  ('⚡', 'Jumper Cables'),
  ('🧰', 'Basic Toolkit'),
  ('🏥', 'First Aid Kit'),
  ('🔦', 'Flashlight'),
  ('🛞', 'Tire Inflator'),
];

class HudScreen extends StatefulWidget {
  const HudScreen({super.key});

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> {
  HudState _state = HudState.normal;
  String _transcript = '';
  String _errorMessage = '';
  String? _activeSurfaceId;
  // Ordered history of surface ids rendered this conversation, oldest first.
  // Each turn appends a new surface below the previous ones so the UI grows
  // downward like a conversation thread (not a replace-in-place).
  final List<String> _surfaces = [];
  // After each surface renders, automatically start listening for the user's
  // spoken feedback so the conversation + UI keeps building hands-free.
  final bool _autoListen = true;
  Timer? _autoListenTimer;
  final Set<String> _selectedTools = {'Spare Tire', 'Car Jack', 'Lug Wrench'};

  late final SurfaceController _controller;
  late final Conversation _conversation;
  late final SpeechService _speech;
  final TtsService _tts = TtsService();
  final CameraService _camera = createCameraService();
  final TextEditingController _customInput = TextEditingController();
  final FireworksTrace _trace = FireworksTrace();
  bool _demoPanelExpanded = true;
  // Live camera mode: Guardian periodically captures frames and updates
  // guidance without the driver tapping anything. _analyzing gates overlap
  // (don't send a new frame while the previous one is still being processed).
  bool _analyzing = false;
  bool _autoCapture = true;
  Timer? _autoCaptureTimer;
  // Set when a voice input starts from camera mode, so the state machine
  // returns to the camera layout (instead of active) once the reply is sent.
  bool _returnToCamera = false;

  // Voice-in is now an overlay, not a full-screen swap: while [_listening] is
  // true the current surface stays visible and the mic captures in the
  // background; a slim listening bar shows the live transcript on top.
  bool _listening = false;

  // Auto-scroll the generated surface to the bottom as components stream in.
  final ScrollController _surfaceScroll = ScrollController();
  final ScrollController _cameraScroll = ScrollController();

  // Voice-out: the spoken script of the last surface, used to debounce so a
  // SurfaceAdded + ComponentsUpdated for the same turn isn't spoken twice.
  String _lastSpoken = '';
  // Whether the current voice-input turn is a follow-up answer (vs. the first
  // emergency report). Decides whether the transcript is sent with the tools
  // context or as a bare reply.
  bool _voiceFollowUp = false;

  @override
  void initState() {
    super.initState();
    _initGenUI();
    _speech = SpeechService();
    _speech.initialize();
  }

  void _initGenUI() {
    // Trimmed catalog: only the components the UI actually uses. The full
    // basic catalog (+ functions) inflates the system prompt to ~77KB, which
    // dominates time-to-first-token on any model. Dropping unused components
    // and all client functions shrinks the prompt sharply → much faster
    // prefill → near-instant surface. catalogId stays the basic one so the
    // model's createSurface still validates.
    final catalog = Catalog(
      [
        BasicCatalogItems.column,
        BasicCatalogItems.row,
        BasicCatalogItems.card,
        BasicCatalogItems.text,
        BasicCatalogItems.icon,
        BasicCatalogItems.button,
        BasicCatalogItems.choicePicker,
        BasicCatalogItems.textField,
        BasicCatalogItems.divider,
        BasicCatalogItems.slider,
        BasicCatalogItems.checkBox,
        BasicCatalogItems.list,
      ],
      catalogId: basicCatalogId,
      systemPromptFragments: [BasicCatalogItems.basicCatalogRules],
    );
    final fullPrompt = PromptBuilder.chat(
      catalog: catalog,
      systemPromptFragments: [_systemPrompt],
    ).systemPromptJoined();

    _controller = SurfaceController(catalogs: [catalog]);
    _conversation = buildConversation(
      controller: _controller,
      systemPrompt: fullPrompt,
      trace: _trace,
    );

    _conversation.events.listen((event) {
      debugPrint('[Guardian/HUD] conversation event: ${event.runtimeType}');
      if (!mounted) return;
      switch (event) {
        case ConversationWaiting():
          setState(() {
            // No full-screen load screen: keep the current layout and let the
            // surface stream its components in. In camera mode just flag
            // "analyzing" beside the live video.
            if (_returnToCamera || _state == HudState.camera) {
              _state = HudState.camera;
              _analyzing = true;
            } else if (_state == HudState.normal) {
              _state = HudState.active;
            }
          });
        case ConversationSurfaceAdded(:final surfaceId, :final definition):
          _sanitizeSurface(definition);
          setState(() {
            _activeSurfaceId = surfaceId;
            if (!_surfaces.contains(surfaceId)) _surfaces.add(surfaceId);
            _state = (_returnToCamera || _state == HudState.camera)
                ? HudState.camera
                : HudState.active;
            _errorMessage = '';
            _analyzing = false;
            _returnToCamera = false;
          });
          _speakGuide(definition);
          _scrollSurfaceToBottom();
          _maybeAutoListen();
        // The controller emits ComponentsUpdated (not SurfaceAdded) when the
        // model re-creates an already-known surfaceId or refreshes components.
        // Without this, the 2nd+ turn would never set _activeSurfaceId and the
        // safety-net would wrongly show the error view. Clearing _errorMessage
        // here also lets an action-triggered follow-up recover from a prior
        // turn's error.
        case ConversationComponentsUpdated(:final surfaceId, :final definition):
          _sanitizeSurface(definition);
          setState(() {
            _activeSurfaceId = surfaceId;
            if (!_surfaces.contains(surfaceId)) _surfaces.add(surfaceId);
            _state = (_returnToCamera || _state == HudState.camera)
                ? HudState.camera
                : HudState.active;
            _errorMessage = '';
            _analyzing = false;
            _returnToCamera = false;
          });
          _speakGuide(definition);
          _scrollSurfaceToBottom();
          _maybeAutoListen();
        case ConversationError(:final error):
          setState(() {
            _analyzing = false;
            // Stay in camera mode on error so the driver can recapture; the
            // error is shown inline in the guidance panel.
            _state = (_returnToCamera || _state == HudState.camera)
                ? HudState.camera
                : HudState.active;
            _returnToCamera = false;
            _errorMessage = error.toString();
          });
        default:
          break;
      }
    });
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _autoListenTimer?.cancel();
    _conversation.dispose();
    _controller.dispose();
    _speech.dispose();
    _tts.dispose();
    _camera.dispose();
    _customInput.dispose();
    _trace.dispose();
    _surfaceScroll.dispose();
    _cameraScroll.dispose();
    super.dispose();
  }

  String get _toolsContext =>
      _selectedTools.isEmpty ? 'No tools available' : _selectedTools.join(', ');

  Future<void> _sendScenario(String text) async {
    final withTools = '$text. Tools in my car: $_toolsContext.';
    setState(() {
      _transcript = text;
      // Fresh scenario → new conversation. Clear the stacked surface history.
      _state = HudState.active;
      _errorMessage = '';
      _activeSurfaceId = null;
      _surfaces.clear();
      _returnToCamera = false;
    });
    _autoListenTimer?.cancel();

    // Safety net: if the transport returns without adding a surface OR emitting
    // an error (e.g. empty/invalid model output), surface a clear message
    // instead of leaving the inline loader up forever.
    try {
      await _conversation
          .sendRequest(ChatMessageFactories.userText(withTools))
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      // ConversationError is emitted separately by the engine for transport
      // failures; this catches anything that escaped (e.g. a timeout).
      debugPrint('[Guardian/HUD] sendRequest threw: $e');
      if (!mounted) return;
      setState(() {
        _state = HudState.active;
        _errorMessage = e.toString();
      });
      return;
    }
    if (!mounted) return;
    if (_state == HudState.active &&
        _activeSurfaceId == null &&
        _errorMessage.isEmpty) {
      debugPrint('[Guardian/HUD] request completed with no surface and no '
          'error — falling back to error view.');
      setState(() {
        _state = HudState.active;
        _errorMessage = _trace.content.isNotEmpty
            ? 'The AI returned no renderable interface. The model output did '
                'not contain a valid A2UI createSurface/updateComponents '
                'message — see the response below.'
            : 'The AI returned no interface and no response content. '
                'See the request/response details below.';
      });
    }
  }

  Future<void> _startListening() => _beginVoiceInput(followUp: false);

  /// Starts the mic as an OVERLAY on top of the current UI (the surface is
  /// NOT replaced). Tap again while listening to cancel. When [followUp] is
  /// true the recognized text is sent as a bare reply (continuing the active
  /// conversation) instead of a fresh scenario with the tools context appended.
  Future<void> _beginVoiceInput({required bool followUp}) async {
    // Toggle off if already listening (a tap on the listening bar / button).
    if (_listening) {
      await _speech.stopListening();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _transcript = '';
      });
      return;
    }
    _tts.stop(); // don't let the HUD speak over the driver's answer
    _voiceFollowUp = followUp;
    _returnToCamera = (_state == HudState.camera);
    setState(() {
      _listening = true;
      _transcript = '';
    });
    await _speech.startListening(
      onResult: (t) => setState(() => _transcript = t),
      onDone: () {
        if (!mounted) return;
        final text = _transcript;
        setState(() => _listening = false);
        if (text.isNotEmpty) {
          if (_voiceFollowUp) {
            _sendFollowUp(text);
          } else {
            _sendScenario(text);
          }
        } else {
          // Nothing recognized — stay where we were.
          setState(() => _returnToCamera = false);
        }
      },
    );
  }

  /// Scrolls the active generated surface to the bottom so newly streamed
  /// components come into view. Runs after the next frame so layout has
  /// reflected the new component sizes.
  void _scrollSurfaceToBottom() {
    final c = _state == HudState.camera ? _cameraScroll : _surfaceScroll;
    if (!c.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (c.hasClients) {
        c.animateTo(c.position.maxScrollExtent,
            duration: 240.ms, curve: Curves.easeOut);
      }
    });
  }

  /// After a surface renders, automatically start listening for the user's
  /// spoken feedback so the conversation (and the stacked UI) keeps building
  /// hands-free. Delayed briefly so the spoken guidance isn't cut off too
  /// sharply; _beginVoiceInput stops TTS when the mic opens for clean input.
  void _maybeAutoListen() {
    _autoListenTimer?.cancel();
    // Don't auto-listen on the active (second) screen — the user taps the
    // speak button to listen there. (Camera mode is also excluded.)
    if (!_autoListen || _listening || _state == HudState.active) return;
    _autoListenTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted || _listening) return;
      _beginVoiceInput(followUp: true);
    });
  }

  /// Sends a follow-up reply in an ongoing conversation (a spoken answer to a
  /// question, or a custom typed follow-up). Unlike [_sendScenario] it does not
  /// append the tools context or reset the surface — the conversation history
  /// already carries both.
  Future<void> _sendFollowUp(String text) async {
    final fromCamera = _returnToCamera;
    setState(() {
      _transcript = text;
      if (fromCamera) {
        _state = HudState.camera;
        _analyzing = true;
      } else {
        // Stay on the active surface; the next surface streams in inline.
        _state = HudState.active;
      }
      _errorMessage = '';
    });
    try {
      await _conversation
          .sendRequest(ChatMessageFactories.userText(text))
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      debugPrint('[Guardian/HUD] follow-up sendRequest threw: $e');
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _state = fromCamera ? HudState.camera : HudState.active;
        _returnToCamera = false;
        _errorMessage = e.toString();
      });
      return;
    }
    if (!mounted) return;
    // Safety net: no surface and no error fired. Clear the analyzing flag and
    // return to the right layout.
    if (_analyzing && _errorMessage.isEmpty && fromCamera) {
      setState(() {
        _analyzing = false;
        _returnToCamera = false;
      });
    } else if (_state == HudState.active &&
        _activeSurfaceId == null &&
        _errorMessage.isEmpty) {
      // Nothing streamed in; leave the inline loader — the safety net in
      // _sendScenario covers fresh scenarios. For follow-ups the prior surface
      // is still showing.
    }
  }

  // ─── Camera vision (live mode) ────────────────────────────────────────────

  Future<void> _openCamera() async {
    if (!_camera.isActive) {
      final ok = await _camera.start();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Camera unavailable. Use HTTPS or localhost and allow camera access.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() => _state = HudState.camera);
    _startAutoCapture();
  }

  void _closeCamera() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _camera.stop();
    if (!mounted) return;
    setState(() {
      _state = _activeSurfaceId != null ? HudState.active : HudState.normal;
      _analyzing = false;
      _listening = false;
    });
  }

  void _toggleAutoCapture() {
    setState(() => _autoCapture = !_autoCapture);
    if (_autoCapture) {
      _startAutoCapture();
    } else {
      _autoCaptureTimer?.cancel();
      _autoCaptureTimer = null;
    }
  }

  /// Begins the periodic capture loop and fires one immediate frame so the
  /// driver sees guidance right away instead of waiting for the first tick.
  void _startAutoCapture() {
    _autoCaptureTimer?.cancel();
    _maybeAutoCapture();
    if (_autoCapture) {
      _autoCaptureTimer =
          Timer.periodic(const Duration(seconds: 7), (_) => _maybeAutoCapture());
    }
  }

  void _maybeAutoCapture() {
    if (!mounted || !_autoCapture || _analyzing || _state != HudState.camera) {
      return;
    }
    _captureAndGuide();
  }

  /// Grabs a frame and sends it as a vision turn. In camera mode the layout
  /// stays put (the guidance panel updates beside the live video); the surface
  /// event handler clears [_analyzing] and speaks the new guidance.
  Future<void> _captureAndGuide() async {
    final dataUrl = await _camera.capture();
    if (dataUrl == null || !mounted) return;
    await _sendCameraFrame(dataUrl);
  }

  Future<void> _sendCameraFrame(String jpegDataUrl) async {
    // data:image/jpeg;base64,<b64> -> bytes
    final comma = jpegDataUrl.indexOf(',');
    final b64 = comma >= 0 ? jpegDataUrl.substring(comma + 1) : jpegDataUrl;
    final Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return; // malformed frame
    }
    const prompt =
        "Here's a live camera frame of what I'm seeing right now. Look at it and guide me on the next step. If the image already shows something you'd otherwise ask about (e.g. which side I'm holding), don't ask — just proceed.";
    final message = ChatMessage.user(
      prompt,
      parts: [DataPart(bytes, mimeType: 'image/jpeg')],
    );
    setState(() {
      _analyzing = true;
      _errorMessage = '';
    });
    try {
      await _conversation
          .sendRequest(message)
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      debugPrint('[Guardian/HUD] camera sendRequest threw: $e');
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _errorMessage = e.toString();
      });
      return;
    }
    if (!mounted) return;
    // Safety net: if no surface event and no error fired, drop the spinner.
    if (_analyzing && _errorMessage.isEmpty) {
      setState(() => _analyzing = false);
    }
  }

  // ─── Voice-out (TTS) ──────────────────────────────────────────────────────

  /// Defensive layout guard: a Row with `align: "stretch"` inside the
  /// vertically-unbounded scroll view forces infinite height and crashes
  /// performLayout. The prompt forbids it, but models occasionally emit it
  /// anyway — rewrite any such Row to `align: "start"` before render. Column
  /// stretch is left alone (it stretches width, which is bounded).
  void _sanitizeSurface(SurfaceDefinition def) {
    for (final c in def.components.values) {
      if (c.type == 'Row' && c.properties['align'] == 'stretch') {
        c.properties['align'] = 'start';
      }
    }
  }

  /// Speaks the guidance from a freshly rendered surface. Debounced by
  /// [_lastSpoken] so a SurfaceAdded + ComponentsUpdated pair for the same
  /// turn isn't read twice.
  void _speakGuide(SurfaceDefinition definition) {
    final script = _extractSpeechText(definition);
    if (script.isEmpty || script == _lastSpoken) return;
    _lastSpoken = script;
    _tts.speak(script);
  }

  /// Walks a surface's components and builds a speakable script from the Text
  /// content (headlines, instructions, the question) plus ChoicePicker option
  /// labels. Button-label Texts are skipped — "Continue" isn't guidance.
  String _extractSpeechText(SurfaceDefinition def) {
    final buttonChildIds = <String>{};
    for (final c in def.components.values) {
      if (c.type == 'Button') {
        final child = c.properties['child'];
        if (child is String) buttonChildIds.add(child);
      }
    }
    final parts = <String>[];
    for (final c in def.components.values) {
      if (c.type == 'Text') {
        if (buttonChildIds.contains(c.id)) continue;
        final t = c.properties['text'];
        if (t is String && t.trim().isNotEmpty) parts.add(t.trim());
      } else if (c.type == 'ChoicePicker') {
        final options = c.properties['options'];
        if (options is List) {
          final labels = <String>[];
          for (final o in options) {
            if (o is Map) {
              final label = o['label'] ?? o['value'];
              if (label is String && label.trim().isNotEmpty) {
                labels.add(label.trim());
              }
            }
          }
          if (labels.isNotEmpty) parts.add('Options: ${labels.join(', ')}');
        }
      }
    }
    // Drop emoji/symbols the synthesizer would read badly, collapse whitespace.
    return parts
        .join('. ')
        .replaceAll(
            RegExp(r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{2190}-\u{21FF}]',
                unicode: true),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _dismiss() {
    _tts.stop();
    _speech.stopListening();
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _autoListenTimer?.cancel();
    _camera.stop();
    setState(() {
      _state = HudState.normal;
      _listening = false;
      _transcript = '';
      _activeSurfaceId = null;
      _surfaces.clear();
      _errorMessage = '';
      _lastSpoken = '';
      _analyzing = false;
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070A0E),
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.space &&
              (_state == HudState.normal ||
                  _state == HudState.active ||
                  _state == HudState.camera)) {
            _beginVoiceInput(followUp: _state != HudState.normal);
          }
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.escape) {
            if (_listening) {
              _beginVoiceInput(followUp: _voiceFollowUp); // toggle off
            } else if (_state == HudState.camera) {
              _closeCamera();
            } else if (_state != HudState.normal) {
              _dismiss();
            }
          }
        },
        child: Stack(children: [
          _mainContent(),
          if (_state != HudState.camera) ...[
            _floatingDemoPanel(),
            if (_state == HudState.normal) ...[_voiceFab(), _cameraFab()],
          ],
          // The active screen has its own listening button in the bottom bar,
          // so don't also stack the top listening overlay there.
          if (_listening && _state != HudState.active) _listeningBar(),
        ]),
      ),
    );
  }

  Widget _mainContent() {
    return SizedBox.expand(
      child: AnimatedSwitcher(
        duration: 600.ms,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: switch (_state) {
          HudState.normal => NormalHud(
              key: const ValueKey('normal'),
              onToggleDemo: () =>
                  setState(() => _demoPanelExpanded = !_demoPanelExpanded),
              demoExpanded: _demoPanelExpanded),
          HudState.active => _activeView(),
          HudState.camera => _cameraMode(key: const ValueKey('camera')),
        },
      ),
    );
  }

  /// Slim overlay shown while the mic is listening. Sits on top of the current
  /// surface (which is NOT replaced) and shows the live transcript; tap to
  /// cancel. The surface keeps rendering/generated UI behind it and auto-scrolls.
  Widget _listeningBar() {
    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => _beginVoiceInput(followUp: _voiceFollowUp),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(40),
              border:
                  Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.2),
                  blurRadius: 20,
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: const Color(0xFF00D4FF), size: 18)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                        begin: 1.0,
                        end: 1.3,
                        duration: 700.ms,
                        curve: Curves.easeInOut),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Text(
                    _transcript.isEmpty ? 'Listening…' : _transcript,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 12),
                Text('tap to cancel',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 200.ms)
          .slideY(begin: -0.3, duration: 200.ms),
    );
  }

  // ─── Active Gen UI surface ────────────────────────────────────────────────

  Widget _activeView() {
    return Container(
      key: const ValueKey('active'),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [Color(0xFF0D1117), Color(0xFF070A0E)],
        ),
      ),
      child: Column(
        children: [
          _activeHeader(),
          Expanded(
            child: _errorMessage.isNotEmpty
                ? _errorView()
                : _surfaces.isEmpty
                    ? _inlineStreamingLoader()
                    : _buildSurfaceStack(),
          ),
          _dismissBar(),
        ],
      ),
    );
  }

  /// Quiet inline placeholder shown while the first surface streams in. No
  /// full-screen load screen — components appear below this as they arrive.
  Widget _inlineStreamingLoader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                color: Color(0xFF00D4FF), strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Generating interface…',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _activeHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFF7C3AED), size: 11),
                SizedBox(width: 6),
                Text('GEN UI · AI GENERATED',
                    style: TextStyle(
                        color: Color(0xFF7C3AED),
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(width: 16),
          const Icon(Icons.shield, color: Color(0xFF00D4FF), size: 14),
          const SizedBox(width: 6),
          const Text('Guardian AI',
              style: TextStyle(
                  color: Color(0xFF00D4FF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          _demoHeaderButton(),
          const Spacer(),
          if (_transcript.isNotEmpty)
            Flexible(
              child: Text('"$_transcript"',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25),
                      fontSize: 12,
                      fontStyle: FontStyle.italic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(width: 12),
          _cameraHeaderButton(),
        ],
      ),
    );
  }

  /// Demo scenarios toggle that lives IN the active header bar (not floating on
  /// top of other buttons). Matches the home-screen demo pill styling.
  Widget _demoHeaderButton() {
    return GestureDetector(
      onTap: () => setState(() => _demoPanelExpanded = !_demoPanelExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFCC00).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: const Color(0xFFFFCC00).withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFFCC00), size: 13),
            const SizedBox(width: 6),
            const Text('Demo',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(
              _demoPanelExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white54,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraHeaderButton() {
    return GestureDetector(
      onTap: _openCamera,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF00FF88).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: const Color(0xFF00FF88).withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, color: Color(0xFF00FF88), size: 14),
            SizedBox(width: 6),
            Text('Show camera',
                style: TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  /// Renders the whole conversation as a vertical stack of surfaces (oldest
  /// first) inside one scroll view. Each turn appends a new surface below the
  /// previous ones, and the view auto-scrolls to the newest at the bottom.
  Widget _buildSurfaceStack() {
    return ValueListenableBuilder<ConversationState>(
      valueListenable: _conversation.state,
      builder: (context, state, child) {
        _scrollSurfaceToBottom();
        return Theme(
          data: _hudTheme(context),
          child: SingleChildScrollView(
            controller: _surfaceScroll,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < _surfaces.length; i++) ...[
                  if (i > 0) const SizedBox(height: 20),
                  _surfaceCard(_surfaces[i]),
                ],
                // Live generating / listening indicator below the last surface.
                if (_listening || _surfaces.isEmpty) ...[
                  const SizedBox(height: 20),
                  _inlineStreamingLoader(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _surfaceCard(String surfaceId) {
    final ctx = _controller.contextFor(surfaceId);
    // Sanitize on every definition change, INSIDE the build path and BEFORE the
    // Surface builds — the conversation-event handler runs too late (the
    // controller has already notified the Surface, which then crashes on
    // align:"stretch"). This wrapper is the parent ValueListenable, so it
    // rebuilds first and mutates the definition in place before the Surface
    // reads it.
    return ValueListenableBuilder<SurfaceDefinition?>(
      valueListenable: ctx.definition,
      builder: (context, def, _) {
        if (def != null) _sanitizeSurface(def);
        return Surface(
          surfaceContext: ctx,
          defaultBuilder: (_) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00D4FF), strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  Widget _dismissBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _beginVoiceInput(followUp: true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF)
                    .withValues(alpha: _listening ? 0.28 : 0.12),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                    color: const Color(0xFF00D4FF)
                        .withValues(alpha: _listening ? 0.7 : 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, color: const Color(0xFF00D4FF), size: 18)
                      .animate(onPlay: _listening
                          ? (c) => c.repeat(reverse: true)
                          : null)
                      .scaleXY(
                          begin: 1.0,
                          end: 1.25,
                          duration: 700.ms,
                          curve: Curves.easeInOut),
                  const SizedBox(width: 10),
                  Text(_listening ? 'Listening…' : 'Speak your answer',
                      style: const TextStyle(
                          color: Color(0xFF00D4FF), fontSize: 14)),
                  const SizedBox(width: 12),
                  Text(_listening ? 'tap to cancel' : '· Space bar',
                      style: TextStyle(
                          color: const Color(0xFF00D4FF)
                              .withValues(alpha: 0.7),
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          TextButton.icon(
            onPressed: _dismiss,
            icon: Icon(Icons.arrow_back,
                size: 13, color: Colors.white.withValues(alpha: 0.2)),
            label: Text('Back to HUD',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF2D2D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('AI ERROR',
                    style: TextStyle(
                        color: Color(0xFFFF2D2D),
                        fontSize: 11,
                        letterSpacing: 2)),
              ),
              const SizedBox(height: 16),
              SelectableText(_errorMessage,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontFamily: 'monospace',
                      height: 1.6)),
              const SizedBox(height: 28),
              _traceSection('REQUEST', _trace.requestBody),
              const SizedBox(height: 20),
              _traceSection(
                  'RESPONSE  ·  ${_trace.statusLine.isNotEmpty ? _trace.statusLine : "(no response)"}',
                  _trace.content),
              if (_trace.liveLog.value.isNotEmpty) ...[
                const SizedBox(height: 20),
                _traceSection('STREAM LOG', _trace.liveLog.value),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _sendScenario(_transcript),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D4FF),
                      foregroundColor: Colors.black,
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _dismiss,
                    child: const Text('Back to HUD',
                        style: TextStyle(color: Colors.white38)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _traceSection(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              body.isEmpty ? '(empty)' : body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Voice FAB ────────────────────────────────────────────────────────────

  Widget _voiceFab() {
    return Positioned(
      bottom: 28,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _startListening,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 0,
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: const Color(0xFF00D4FF), size: 18)
                    .animate(onPlay: _listening
                        ? (c) => c.repeat(reverse: true)
                        : null)
                    .scaleXY(
                        begin: 1.0,
                        end: 1.3,
                        duration: 700.ms,
                        curve: Curves.easeInOut),
                const SizedBox(width: 10),
                Text(_listening ? 'Listening…' : 'Tap to speak',
                    style:
                        const TextStyle(color: Color(0xFF00D4FF), fontSize: 14)),
                const SizedBox(width: 14),
                Text('·',
                    style: const TextStyle(
                        color: Color(0xFF00D4FF), fontSize: 14)),
                const SizedBox(width: 14),
                Text(_listening ? 'tap to cancel' : 'Space bar',
                    style: const TextStyle(
                        color: Color(0xFF00D4FF),
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 600.ms, delay: 400.ms)
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(
              begin: 1.0, end: 1.02, duration: 2000.ms, curve: Curves.easeInOut),
    );
  }

  // ─── Camera FAB (normal HUD) ──────────────────────────────────────────────

  Widget _cameraFab() {
    return Positioned(
      bottom: 28,
      right: 28,
      child: GestureDetector(
        onTap: _openCamera,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF00FF88).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(
                color: const Color(0xFF00FF88).withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FF88).withValues(alpha: 0.15),
                blurRadius: 20,
              )
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam, color: Color(0xFF00FF88), size: 18),
              SizedBox(width: 10),
              Text('Show camera',
                  style: TextStyle(color: Color(0xFF00FF88), fontSize: 14)),
            ],
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 600.ms, delay: 500.ms),
    );
  }

  // ─── Camera mode (live) ────────────────────────────────────────────────────

  Widget _cameraMode({Key? key}) {
    return Container(
      key: key,
      color: const Color(0xFF070A0E),
      child: Column(
        children: [
          _cameraModeHeader(),
          Expanded(child: _cameraModeBody()),
          _cameraModeControls(),
        ],
      ),
    );
  }

  Widget _cameraModeHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF00FF88).withValues(alpha: 0.06),
        border: Border(
            bottom: BorderSide(color: const Color(0xFF00FF88).withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam, color: Color(0xFF00FF88), size: 18),
          const SizedBox(width: 10),
          const Text('Live camera · Guardian is watching',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          if (_analyzing)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      color: Color(0xFF00FF88), strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('analyzing…',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12)),
              ],
            ),
          const Spacer(),
          GestureDetector(
            onTap: _toggleAutoCapture,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (_autoCapture
                        ? const Color(0xFF00FF88)
                        : Colors.white)
                    .withValues(alpha: _autoCapture ? 0.12 : 0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: (_autoCapture
                            ? const Color(0xFF00FF88)
                            : Colors.white)
                        .withValues(alpha: 0.3)),
              ),
              child: Text(
                _autoCapture ? 'Auto · ON' : 'Auto · OFF',
                style: TextStyle(
                    color: _autoCapture
                        ? const Color(0xFF00FF88)
                        : Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: _closeCamera,
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Close camera'),
          ),
        ],
      ),
    );
  }

  Widget _cameraModeBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _cameraPreview()),
          const SizedBox(width: 16),
          Expanded(flex: 6, child: _cameraGuidancePanel()),
        ],
      ),
    );
  }

  Widget _cameraPreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.black,
        child: _camera.isActive
            ? HtmlElementView(viewType: _camera.viewTypeId)
            : Center(
                child: Text(
                  'Camera unavailable\nUse HTTPS or localhost and allow camera access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13),
                ),
              ),
      ),
    );
  }

  /// Sanitized Surface for the camera guidance panel (see _surfaceCard).
  Widget _cameraSurface(String surfaceId) {
    final ctx = _controller.contextFor(surfaceId);
    return ValueListenableBuilder<SurfaceDefinition?>(
      valueListenable: ctx.definition,
      builder: (context, def, _) {
        if (def != null) _sanitizeSurface(def);
        return Surface(
          surfaceContext: ctx,
          defaultBuilder: (_) => const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF00D4FF), strokeWidth: 2),
          ),
        );
      },
    );
  }

  Widget _cameraGuidancePanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        children: [
          if (_activeSurfaceId != null)
            Theme(
              data: _hudTheme(context),
              child: SingleChildScrollView(
                controller: _cameraScroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 56),
                child: _cameraSurface(_activeSurfaceId!),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _camera.isActive
                      ? 'Point the camera at the problem.\nGuardian will watch and guide you.'
                      : 'Starting camera…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 14,
                      height: 1.5),
                ),
              ),
            ),
          if (_analyzing && _activeSurfaceId == null)
            const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF00FF88), strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _cameraModeControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: _captureAndGuide,
            icon: const Icon(Icons.camera, size: 20),
            label: const Text('Capture now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF88),
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(56),
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _beginVoiceInput(followUp: true),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF)
                    .withValues(alpha: _listening ? 0.28 : 0.12),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                    color: const Color(0xFF00D4FF)
                        .withValues(alpha: _listening ? 0.7 : 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, color: const Color(0xFF00D4FF), size: 18)
                      .animate(onPlay: _listening
                          ? (c) => c.repeat(reverse: true)
                          : null)
                      .scaleXY(
                          begin: 1.0,
                          end: 1.3,
                          duration: 700.ms,
                          curve: Curves.easeInOut),
                  const SizedBox(width: 10),
                  Text(_listening ? 'Listening…' : 'Speak',
                      style: const TextStyle(
                          color: Color(0xFF00D4FF),
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Text(_listening ? 'tap to cancel' : '· Space',
                      style: TextStyle(
                          color: const Color(0xFF00D4FF)
                              .withValues(alpha: 0.7),
                          fontSize: 12,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ─── Demo panel ───────────────────────────────────────────────────────────

  Widget _floatingDemoPanel() {
    // On the home screen the toggle lives in the top bar (left, next to the
    // time), so here we only render the expanded panel, dropped just below that
    // top bar on the left. In the active surface state there's no top-bar
    // toggle, so we render the floating toggle + panel on the top-right.
    if (_state == HudState.normal) {
      if (!_demoPanelExpanded) return const SizedBox.shrink();
      return Positioned(
        top: 84,
        left: 28,
        child: _panel(),
      );
    }
    // Active surface state: the toggle lives in the header bar (left), so here
    // we only render the expanded panel, dropped just below the header on the
    // left.
    if (!_demoPanelExpanded) return const SizedBox.shrink();
    return Positioned(
      top: 72,
      left: 28,
      child: _panel(),
    );
  }

  Widget _panel() {
    final categories = <String, List<_Scenario>>{};
    for (final s in _scenarios) {
      categories.putIfAbsent(s.category, () => []).add(s);
    }

    return Container(
      width: 300,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - 120),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8))
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...categories.entries.map((entry) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(entry.key.toUpperCase(),
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.3),
                              fontSize: 9,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w600)),
                    ),
                    ...entry.value.map((s) => _scenarioTile(s)),
                    const SizedBox(height: 8),
                  ],
                )),
            const Divider(color: Colors.white12, height: 24),
            _toolsSection(),
            const Divider(color: Colors.white12, height: 24),
            _customInputSection(),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.05);
  }

  Widget _scenarioTile(_Scenario s) {
    return GestureDetector(
      onTap: () => _sendScenario(s.prompt),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Text(s.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.3)),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 10, color: Colors.white.withValues(alpha: 0.2)),
          ],
        ),
      ),
    );
  }

  Widget _toolsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('MY TOOLS',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 9,
                    letterSpacing: 2)),
            const Spacer(),
            Text('${_selectedTools.length} selected',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2), fontSize: 10)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _allTools.map((t) {
            final sel = _selectedTools.contains(t.$2);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) {
                  _selectedTools.remove(t.$2);
                } else {
                  _selectedTools.add(t.$2);
                }
              }),
              child: AnimatedContainer(
                duration: 200.ms,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0xFF00D4FF).withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: sel
                        ? const Color(0xFF00D4FF).withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Text('${t.$1} ${t.$2}',
                    style: TextStyle(
                        color: sel ? const Color(0xFF00D4FF) : Colors.white54,
                        fontSize: 10,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.normal)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _customInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CUSTOM SCENARIO',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 9,
                letterSpacing: 2)),
        const SizedBox(height: 8),
        TextField(
          controller: _customInput,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Describe your emergency...',
            hintStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF00D4FF)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: IconButton(
              icon: const Icon(Icons.send_rounded,
                  size: 16, color: Color(0xFF00D4FF)),
              onPressed: () {
                if (_customInput.text.isNotEmpty) {
                  _sendScenario(_customInput.text);
                  _customInput.clear();
                }
              },
            ),
          ),
          onSubmitted: (v) {
            if (v.isNotEmpty) {
              _sendScenario(v);
              _customInput.clear();
            }
          },
          maxLines: 2,
          minLines: 1,
        ),
      ],
    );
  }

  // ─── Theme ────────────────────────────────────────────────────────────────

  // Native macOS dark-mode aesthetic for the generated surface: system-blue
  // accent, translucent rounded cards, 8px corners, SF-style tight typography,
  // quiet dividers — like a Mac app, not a neon car HUD.
  // Generated-surface theme matched to the home HUD: dark translucent cards,
  // cyan (#00D4FF) accent, green secondary — same palette as NormalHud.
  ThemeData _hudTheme(BuildContext context) {
    const accent = Color(0xFF00D4FF);
    const green = Color(0xFF00FF88);
    const red = Color(0xFFFF2D2D);
    const cardBg = Color(0xFF121821);
    return Theme.of(context).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Colors.black,
        secondary: green,
        error: red,
        surface: cardBg,
        onSurface: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.black,
          // Finite min width so buttons can sit inside a Row without forcing
          // infinite width (Size.fromHeight uses width=∞ and explodes in a Row).
          minimumSize: const Size(96, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(80, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: const TextStyle(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(
            color: accent, fontSize: 14, fontWeight: FontWeight.w700),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
        backgroundColor: Colors.white.withValues(alpha: 0.04),
        selectedColor: accent.withValues(alpha: 0.18),
        showCheckmark: false,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1,
        space: 10,
      ),
      textTheme: TextTheme(
        headlineLarge: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            height: 1.15),
        headlineMedium: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2),
        headlineSmall: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700),
        bodyLarge: const TextStyle(
            color: Colors.white, fontSize: 16, height: 1.4),
        bodyMedium: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 15,
            height: 1.4),
        bodySmall: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13),
      ),
    );
  }
}
