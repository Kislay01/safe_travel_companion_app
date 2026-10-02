# TravelGuard

A Flutter + Firebase safety app that connects a traveller (child) with their guardians.

**Features**
- Separate Child and Guardian accounts (Firebase Auth, email/password)
- Guardian ↔ child linking through requests you accept or reject
- Live location sharing in the background, shown on the guardian's map
- SOS: hold for 3 seconds to call your primary contact
- Journey planning with route drawing and spoken turn-by-turn directions
- Real-time chat between linked guardians and children
- Emergency contacts, primary contact selection, dark mode

**Stack:** Flutter (Dart), Firebase Auth, Cloud Firestore, Google Maps SDK, Routes API.

## Getting started

See [SETUP.md](SETUP.md) to create your own Firebase project and Maps key, then:

```bash
cd sos_system
flutter pub get
flutter run --dart-define-from-file=secrets.json
```
