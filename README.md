# TravelGuard

A Flutter + Firebase safety app that connects a traveller (child) with their guardians.

**Features**
- Separate Child and Guardian accounts (Firebase Auth, email/password, password reset)
- Link accounts by request or with an **invite code** (share on WhatsApp, enter at sign-up)
- Live location sharing in the background, shown on the guardian's map
- **Journeys**: Google-style place suggestions, route + spoken turn-by-turn directions,
  guardians alerted when a journey **starts**, **completes** (auto-detected on arrival) or is ended early;
  guardians see the child's route and live position
- **SOS**: hold for 3 s, or say *"help me"* (Voice SOS) → guardians get an alert with a map link,
  then the primary contact is called
- **"Are you OK?" check-in**: a guardian pings the child; the child's phone vibrates and they reply
  *I'm OK* or *Need help* (which triggers SOS)
- Journey history for the child and for each guardian
- Real-time chat, emergency contacts, primary contact, dark mode

**Stack:** Flutter (Dart), Firebase Auth, Cloud Firestore, Google Maps SDK, Routes API, Places API (New), speech_to_text, flutter_local_notifications.

## Getting started

See [SETUP.md](SETUP.md) to create your own Firebase project and Maps key, then:

```bash
cd sos_system
flutter pub get
flutter run --dart-define-from-file=secrets.json
```
