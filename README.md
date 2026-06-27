# GuardianHUD

**Generative HUD — AI-powered emergency assistant for drivers**
Flutter × Gemini AI · Automotive Track · Flutter SF × VGV Hackathon 2026

---

## What it does

GuardianHUD is a voice-first, AI-native heads-up display for drivers. When a driver speaks an emergency situation, Gemini classifies the event and generates a tailored HUD interface in real time — the layout, alerts, action cards, and guidance are constructed from AI output, not hardcoded screens.

A collision generates a different HUD than a medical event. A breakdown at night shows different actions than a minor fender bender. That is Generative UI applied to driver safety.

---

## Gen UI architecture

The same renderer produces completely different HUDs for:
- Collision → impact severity card, call 911, nearest hospital
- Medical → symptom triage, emergency contact, calm guidance
- Breakdown → location sharing, roadside assistance, safety steps
- Routine → calm informational HUD, no friction

---

## Key features

| Feature | What it does |
|---|---|
| Voice input | Speak the situation hands-free via speech_to_text |
| Gemini classification | Detects emergency type and severity from voice + context |
| Generative HUD spec | Gemini generates layout, color mood, and action cards per scenario |
| Adaptive action cards | AI-generated next steps specific to the detected situation |
| Mock offline mode | Full demo works without API key |

---

## Quick start

```bash
# 1. Clone
git clone https://github.com/tejkiranyenugunti-spec/AutoGenUI.git
cd AutoGenUI

# 2. Install
flutter pub get

# 3. Add API key — create .env in project root
echo "GEMINI_API_KEY=your_key_here" > .env

# 4. Run
flutter run -d chrome --web-port=5555
```

Open `http://localhost:5555` in Chrome.
Get a free key at [aistudio.google.com](https://aistudio.google.com)
App runs in mock mode without a key — full demo works offline.

---

## 

**A. Collision (45s)**
Say: *I just had a crash, airbag deployed, I think I am hurt*
→ Gemini classifies → HUD generates → call 911, share location, nearest hospital

**B. Medical (30s)**
Say: *I am feeling chest pain and dizzy while driving*
→ Completely different HUD — symptom triage, emergency contact, calm copy

**C. Breakdown (20s)**
Say: *My car broke down on the highway at night*
→ Different HUD again — location sharing, roadside assistance steps

**D. Routine contrast (15s)**
Say: *I need the nearest gas station*
→ Calm informational HUD, no emergency cards — proves UI is generated not hardcoded

---

## Project structure
lib/

main.dart

core/

services/      # Gemini API calls, voice service

models/        # HUD spec model, emergency classification

providers/     # Riverpod state

theme/         # Design tokens, color moods

features/

hud/           # Generative HUD renderer

home/          # Driver home screen

assistant/     # Voice assistant interface

assets/

images/

bg-image.jpg

---

## Stack

Flutter · Dart · Gemini REST API · google_generative_ai · speech_to_text · flutter_animate · genui · permission_handler · flutter_dotenv

---

## Hackathon track

**Automotive** — Generative HUDs, adaptive dashboards, voice-to-UI

GuardianHUD directly addresses the track brief: a voice-to-UI system where the interface is generated at runtime from AI output, responding to driver context and emergency type — not a fixed screen per scenario.

---

Built for Flutter SF × VGV Hackathon, June 26 2026, San Francisco.
GuardianHUD is a demo application. Not for use in real emergencies.
