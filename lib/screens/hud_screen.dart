import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:genui/genui.dart';

import '../services/fireworks_transport.dart';
import '../services/speech_service.dart';
import '../widgets/normal_hud.dart';
import '../widgets/voice_indicator.dart';

enum HudState { normal, listening, processing, active }

const _hudSystemPrompt = '''
You are an AI safety assistant embedded in a dark-themed car HUD (heads-up display).
When a driver reports an emergency, you generate a dynamic safety UI using A2UI widgets.

DESIGN RULES:
- Dark background (#0A0A0F), high contrast white text
- Steps must be numbered and ordered by urgency
- Keep all text SHORT — driver is stressed and moving
- Always include at least one action button (Call 911, Roadside Assist, etc.)
- Use Column as root, Row for step cards and action buttons

EMERGENCY RESPONSE PATTERN:
1. Start with a bold Text widget showing the emergency type in ALL CAPS (e.g. "🚨 TIRE BLOWOUT")
2. Show 3-5 steps as Card widgets in a Row — each Card has a number + emoji + short title + one-line description
3. Show action Buttons in a Row at the bottom
4. Add a small italic Text for additional context (tool-aware)

TOOL AWARENESS:
- If driver HAS a spare tire and jack → show full tire-change step sequence
- If driver has NO spare → skip change steps, show roadside assist Button
- If medical emergency → first Button must be "Call 911"
- If being followed → never suggest stopping at isolated places

SEVERITY COLORS (use as hint text in Text hints):
- critical → h1
- high → h2
- medium → h3
''';

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

  late final SurfaceController _controller;
  late final Conversation _conversation;
  late final SpeechService _speech;

  final TextEditingController _demoInput = TextEditingController();

  final List<String> _scenarios = [
    'My tire just blew out, I have a spare tire and jack',
    'I think I\'m having a heart attack',
    'Someone is following me, I\'m scared',
    'The road ahead is completely flooded',
    'My engine is making a horrible noise and smoking',
    'My tire blew out and I have no spare',
  ];

  @override
  void initState() {
    super.initState();

    final catalog = BasicCatalogItems.asNoAssetCatalog(
      systemPromptFragments: [_hudSystemPrompt],
    );

    final systemPrompt = PromptBuilder.chat(
      catalog: catalog,
      systemPromptFragments: [_hudSystemPrompt],
    ).systemPromptJoined();

    _controller = SurfaceController(catalogs: [catalog]);

    _conversation = buildConversation(
      controller: _controller,
      systemPrompt: systemPrompt,
    );

    _conversation.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case ConversationWaiting():
          setState(() => _state = HudState.processing);
        case ConversationSurfaceAdded(:final surfaceId):
          setState(() {
            _activeSurfaceId = surfaceId;
            _state = HudState.active;
          });
        case ConversationError(:final error):
          setState(() {
            _state = HudState.active;
            _errorMessage = error.toString();
          });
        default:
          break;
      }
    });

    _speech = SpeechService();
    _speech.initialize();
  }

  @override
  void dispose() {
    _conversation.dispose();
    _controller.dispose();
    _speech.dispose();
    _demoInput.dispose();
    super.dispose();
  }

  Future<void> _sendScenario(String text) async {
    setState(() {
      _transcript = text;
      _state = HudState.processing;
      _errorMessage = '';
    });
    await _conversation.sendRequest(ChatMessageFactories.userText(text));
  }

  Future<void> _startListening() async {
    setState(() {
      _state = HudState.listening;
      _transcript = '';
    });

    await _speech.startListening(
      onResult: (text) => setState(() => _transcript = text),
      onDone: () {
        if (_transcript.isNotEmpty) _sendScenario(_transcript);
      },
    );
  }

  void _dismiss() {
    setState(() {
      _state = HudState.normal;
      _transcript = '';
      _activeSurfaceId = null;
      _errorMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: (e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.space &&
              _state == HudState.normal) {
            _startListening();
          }
        },
        child: Stack(
          children: [
            _mainContent(),
            _demoPanel(),
            if (_state == HudState.normal) _voiceButton(),
          ],
        ),
      ),
    );
  }

  Widget _mainContent() {
    return AnimatedSwitcher(
      duration: 500.ms,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: switch (_state) {
        HudState.normal => const NormalHud(key: ValueKey('normal')),
        HudState.listening => VoiceListeningOverlay(
            key: const ValueKey('listening'),
            transcript: _transcript,
          ),
        HudState.processing => ProcessingOverlay(
            key: const ValueKey('processing'),
            transcript: _transcript,
          ),
        HudState.active => _genUiSurface(),
      },
    );
  }

  Widget _genUiSurface() {
    if (_errorMessage.isNotEmpty) {
      return _errorView();
    }

    return Container(
      key: const ValueKey('active'),
      color: const Color(0xFF0A0A0F),
      child: Column(
        children: [
          _activeHeader(),
          Expanded(
            child: _activeSurfaceId != null
                ? _buildSurface(_activeSurfaceId!)
                : const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF00D4FF),
                      strokeWidth: 2,
                    ),
                  ),
          ),
          _dismissBar(),
        ],
      ),
    );
  }

  Widget _buildSurface(String surfaceId) {
    return ValueListenableBuilder<ConversationState>(
      valueListenable: _conversation.state,
      builder: (context, state, _) {
        final surfaceContext = _controller.contextFor(surfaceId);
        if (surfaceContext == null) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF00D4FF),
              strokeWidth: 2,
            ),
          );
        }

        return Theme(
          data: _hudTheme(context),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Surface(
              surfaceContext: surfaceContext,
              defaultBuilder: (_) => const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00D4FF),
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _activeHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: Color(0xFF00D4FF), size: 12),
                SizedBox(width: 6),
                Text(
                  'GEN UI — AI GENERATED',
                  style: TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '"$_transcript"',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _dismissBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: TextButton.icon(
        onPressed: _dismiss,
        icon: Icon(Icons.close, size: 14, color: Colors.white.withValues(alpha: 0.25)),
        label: Text(
          'Dismiss — return to HUD',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Container(
      key: const ValueKey('error'),
      color: const Color(0xFF0A0A0F),
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ERROR',
            style: TextStyle(
              color: Color(0xFFFF2D2D),
              fontSize: 13,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            _errorMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: _dismiss,
            child: const Text(
              '← Back',
              style: TextStyle(color: Color(0xFF00D4FF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceButton() {
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
              color: const Color(0xFF00D4FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: const Color(0xFF00D4FF).withValues(alpha: 0.4),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: Color(0xFF00D4FF), size: 18),
                SizedBox(width: 10),
                Text(
                  'Hold to speak  ·  Space bar',
                  style: TextStyle(color: Color(0xFF00D4FF), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 600.ms, delay: 300.ms),
    );
  }

  Widget _demoPanel() {
    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        width: 270,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DEMO SCENARIOS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            ..._scenarios.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () => _sendScenario(s),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Text(
                      '"$s"',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: Colors.white12),
            const SizedBox(height: 6),
            TextField(
              controller: _demoInput,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Type custom scenario...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF00D4FF)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(
                    Icons.send,
                    size: 14,
                    color: Color(0xFF00D4FF),
                  ),
                  onPressed: () {
                    if (_demoInput.text.isNotEmpty) {
                      _sendScenario(_demoInput.text);
                      _demoInput.clear();
                    }
                  },
                ),
              ),
              onSubmitted: (v) {
                if (v.isNotEmpty) {
                  _sendScenario(v);
                  _demoInput.clear();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _hudTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00D4FF),
        secondary: Color(0xFF00FF88),
        error: Color(0xFFFF2D2D),
        surface: Color(0xFF0D1117),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.05),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF2D2D),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
        headlineMedium: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: Colors.white,
          fontSize: 14,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: Color(0xFFAAAAAA),
          fontSize: 12,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: Color(0xFF888888),
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
