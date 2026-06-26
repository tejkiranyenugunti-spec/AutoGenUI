import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:genui/genui.dart';

import '../services/fireworks_transport.dart';
import '../services/speech_service.dart';
import '../widgets/normal_hud.dart';
import '../widgets/voice_indicator.dart';

enum HudState { onboarding, normal, listening, processing, active }

// ---------------------------------------------------------------------------
// System prompt — detailed genui instructions for rich dark HUD UI
// ---------------------------------------------------------------------------
const _systemPrompt = '''
You are Guardian AI — an emergency safety assistant embedded in a dark automotive HUD for drivers.

The framework gives you the full A2UI component schema and message protocol (createSurface + updateComponents, fenced ```json blocks, a unique surfaceId per response, a root component, each component's required properties). Use it directly. Output ONLY the A2UI messages — no plan, no reasoning, no preamble, no restating the input. Generate the surface immediately.

DRIVING-FIRST DESIGN — the driver cannot look at or tap small targets.
- NEVER use Tabs. The driver cannot switch tabs while driving. Present everything as ONE linear, glanceable, scrollable flow.
- GO BIG. This is a car HUD, not a phone form: large text, fat buttons, chunky chips, full-width cards that stack edge-to-edge with little/no gap between them. The driver is glancing, not reading — every tap target must be oversized.
- Build a real visual interface, never a word dump: use Card as a padded container to GROUP related content (Icon + title + sub-items in one Card), Icon for visual cues (warning, call, locationOn, error, lock, lockOpen, info, refresh), Divider to separate sections, Row/Column with justify ("center","spaceBetween") and align ("center","stretch") for deliberate spacing.
- HIERARCHY with Text variants: one h1 headline with an Icon beside it, h2 section headers, h3 item titles, caption notes, body one-liners. Keep each Text ~6 words.
- Make the single most important action a "primary" Button; secondary actions "borderless" Buttons; use "spaceBetween" so they aren't crammed together.
- Adapt structure and density to the situation; do not reuse a fixed template.

TWO-WAY CONVERSATION — use interactivity ONLY when you genuinely need info from the driver that changes the plan. If the emergency and available tools already tell you what to do, SKIP questions and go straight to instructions + actions. Never collect an input and then stop, and NEVER re-ask something the driver already answered.
- When you DO need info (symptoms, who's hurt, location, ability to move), ask ONE question at a time. Use a ChoicePicker ("displayStyle":"chips","variant":"mutuallyExclusive") for fixed options, or a TextField for free text like a location. Give the input a data path and use that SAME path in the submit button:
  - ChoicePicker: {"id":"picker","component":"ChoicePicker","path":"answer","displayStyle":"chips","variant":"mutuallyExclusive","options":[{"value":"yes","label":"Yes"},{"value":"no","label":"No"}]}
  - TextField:   {"id":"loc","component":"TextField","variant":"shortText","value":{"path":"answer"},"label":"Where are you?"}
  - Submit Button: {"id":"submit","component":"Button","child":"submitText","variant":"primary","action":{"event":{"name":"answer_submitted","context":{"answer":{"path":"answer"}}}}}  — the context MUST bind the exact same path as the input.
- ALWAYS set "sendDataModel": true on createSurface when you render ANY input. Without it the input's value is never stored, the button context resolves empty, and you will receive a blank answer.
- When you receive `[USER_ACTION] {"name":"...","context":{"answer":"..."}}`, the context already holds the driver's answer. USE IT — do NOT ask the same question again. Generate the NEXT surface: the next clarifying question, step-by-step instructions, or the final call-911 / roadside / move-to-safety action.
- A ChoicePicker with "variant":"multipleSelection" works as a mark-each-step-done checklist.
- Keep each turn short and glanceable. Prioritize the call-911 / roadside / move-to-safety action once enough is known.
- Adapt to available tools: only instruct actions the driver can perform with what they have; otherwise offer the appropriate assistance action. Never advise stopping in an unsafe or isolated location.

CORRECTNESS (the parser rejects unknown fields):
- Every Button MUST reference a SEPARATE Text child by id, e.g. {"id":"btn1","component":"Button","child":"btn1text","variant":"primary","action":{"event":{"name":"call_911"}}} plus {"id":"btn1text","component":"Text","text":"📞 Call 911"}.
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
  HudState _state = HudState.onboarding;
  String _transcript = '';
  String _errorMessage = '';
  String? _activeSurfaceId;
  final Set<String> _selectedTools = {'Spare Tire', 'Car Jack', 'Lug Wrench'};

  late final SurfaceController _controller;
  late final Conversation _conversation;
  late final SpeechService _speech;
  final TextEditingController _customInput = TextEditingController();
  final FireworksTrace _trace = FireworksTrace();
  bool _demoPanelExpanded = true;

  @override
  void initState() {
    super.initState();
    _initGenUI();
    _speech = SpeechService();
    _speech.initialize();
  }

  void _initGenUI() {
    final catalog = BasicCatalogItems.asNoAssetCatalog();
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
          setState(() => _state = HudState.processing);
        case ConversationSurfaceAdded(:final surfaceId):
          setState(() {
            _activeSurfaceId = surfaceId;
            _state = HudState.active;
            _errorMessage = '';
          });
        // The controller emits ComponentsUpdated (not SurfaceAdded) when the
        // model re-creates an already-known surfaceId or refreshes components.
        // Without this, the 2nd+ turn would never set _activeSurfaceId and the
        // safety-net would wrongly show the error view. Clearing _errorMessage
        // here also lets an action-triggered follow-up recover from a prior
        // turn's error.
        case ConversationComponentsUpdated(:final surfaceId):
          setState(() {
            _activeSurfaceId = surfaceId;
            _state = HudState.active;
            _errorMessage = '';
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
  }

  @override
  void dispose() {
    _conversation.dispose();
    _controller.dispose();
    _speech.dispose();
    _customInput.dispose();
    _trace.dispose();
    super.dispose();
  }

  String get _toolsContext =>
      _selectedTools.isEmpty ? 'No tools available' : _selectedTools.join(', ');

  Future<void> _sendScenario(String text) async {
    final withTools = '$text. Tools in my car: $_toolsContext.';
    setState(() {
      _transcript = text;
      _state = HudState.processing;
      _errorMessage = '';
      _activeSurfaceId = null;
    });

    // Safety net: if the transport returns without adding a surface OR emitting
    // an error (e.g. empty/invalid model output), surface a clear message
    // instead of leaving the spinner up forever.
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
    if (_state == HudState.processing &&
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

  Future<void> _startListening() async {
    setState(() {
      _state = HudState.listening;
      _transcript = '';
    });
    await _speech.startListening(
      onResult: (t) => setState(() => _transcript = t),
      onDone: () {
        if (_transcript.isNotEmpty) _sendScenario(_transcript);
      },
    );
  }

  void _dismiss() => setState(() {
        _state = HudState.normal;
        _transcript = '';
        _activeSurfaceId = null;
        _errorMessage = '';
      });

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
              _state == HudState.normal) {
            _startListening();
          }
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.escape &&
              _state != HudState.normal) {
            _dismiss();
          }
        },
        child: Stack(children: [
          _mainContent(),
          if (_state != HudState.onboarding) ...[
            _floatingDemoPanel(),
            if (_state == HudState.normal) _voiceFab(),
          ],
          if (_state == HudState.onboarding) _onboarding(),
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
          HudState.onboarding || HudState.normal =>
            const NormalHud(key: ValueKey('normal')),
          HudState.listening => VoiceListeningOverlay(
              key: const ValueKey('listening'), transcript: _transcript),
          HudState.processing => ProcessingOverlay(
              key: const ValueKey('processing'),
              transcript: _transcript,
              trace: _trace),
          HudState.active => _activeView(),
        },
      ),
    );
  }

  // ─── Onboarding ──────────────────────────────────────────────────────────

  Widget _onboarding() {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield, color: Color(0xFF00D4FF), size: 28),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Guardian HUD',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w700)),
                      Text('AI-powered emergency assistant',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text('What tools do you have in your car?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Guardian adapts its response based on what\'s available to you.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allTools.map((t) {
                  final selected = _selectedTools.contains(t.$2);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedTools.remove(t.$2);
                      } else {
                        _selectedTools.add(t.$2);
                      }
                    }),
                    child: AnimatedContainer(
                      duration: 200.ms,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF00D4FF).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF00D4FF).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.$1, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(t.$2,
                              style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF00D4FF)
                                      : Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => setState(() => _state = HudState.normal),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D4FF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('Launch HUD',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'You can update tools anytime from the side panel',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 500.ms).scale(begin: const Offset(0.95, 0.95)),
      ),
    );
  }

  // ─── Active Gen UI surface ────────────────────────────────────────────────

  Widget _activeView() {
    return Container(
      key: const ValueKey('active'),
      color: const Color(0xFF070A0E),
      child: Column(
        children: [
          _activeHeader(),
          Expanded(
            child: _errorMessage.isNotEmpty
                ? _errorView()
                : _activeSurfaceId != null
                    ? _buildSurface(_activeSurfaceId!)
                    : const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF00D4FF), strokeWidth: 2)),
          ),
          _dismissBar(),
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
        ],
      ),
    );
  }

  Widget _buildSurface(String surfaceId) {
    return ValueListenableBuilder<ConversationState>(
      valueListenable: _conversation.state,
      builder: (context, state, child) {
        final ctx = _controller.contextFor(surfaceId);
        return Theme(
          data: _hudTheme(context),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            child: Surface(
              surfaceContext: ctx,
              defaultBuilder: (_) => const Center(
                child: CircularProgressIndicator(
                    color: Color(0xFF00D4FF), strokeWidth: 2),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dismissBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _dismiss,
            icon: Icon(Icons.arrow_back,
                size: 13, color: Colors.white.withValues(alpha: 0.2)),
            label: Text('Back to HUD',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.2), fontSize: 12)),
          ),
          Text('  ·  ',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.1), fontSize: 12)),
          Text('Press ESC',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.15), fontSize: 11)),
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
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, color: Color(0xFF00D4FF), size: 18),
                SizedBox(width: 10),
                Text('Tap to speak',
                    style: TextStyle(color: Color(0xFF00D4FF), fontSize: 14)),
                SizedBox(width: 14),
                Text('·',
                    style: TextStyle(
                        color: Color(0xFF00D4FF), fontSize: 14)),
                SizedBox(width: 14),
                Text('Space bar',
                    style: TextStyle(
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

  // ─── Demo panel ───────────────────────────────────────────────────────────

  Widget _floatingDemoPanel() {
    return Positioned(
      top: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _panelToggle(),
          if (_demoPanelExpanded) ...[
            const SizedBox(height: 8),
            _panel(),
          ],
        ],
      ),
    );
  }

  Widget _panelToggle() {
    return GestureDetector(
      onTap: () => setState(() => _demoPanelExpanded = !_demoPanelExpanded),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFFFCC00), size: 14),
            const SizedBox(width: 6),
            const Text('Demo Scenarios',
                style: TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(
              _demoPanelExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.white38,
              size: 16,
            ),
          ],
        ),
      ),
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

  ThemeData _hudTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF00D4FF),
        secondary: Color(0xFF00FF88),
        error: Color(0xFFFF2D2D),
        // Card renders with colorScheme.surface, so this must contrast with the
        // 0xFF070A0E page background or cards vanish into it.
        surface: Color(0xFF121821),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF121821),
        elevation: 0,
        // No gap between stacked cards — the driver sees one continuous
        // chunky panel, not a airy phone-style list.
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF2D2D),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(72),
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF00D4FF),
          minimumSize: const Size.fromHeight(64),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 1.5,
        space: 8,
      ),
      textTheme: TextTheme(
        headlineLarge: const TextStyle(
            color: Colors.white,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            height: 1.15),
        headlineMedium: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 2),
        headlineSmall: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700),
        bodyLarge: const TextStyle(
            color: Colors.white, fontSize: 18, height: 1.45),
        bodyMedium: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 16,
            height: 1.4),
        bodySmall: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
            fontStyle: FontStyle.italic),
      ),
    );
  }
}
