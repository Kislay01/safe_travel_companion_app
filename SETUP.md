# Setup: use your own Firebase + Google Maps keys

No keys are committed. You supply two git-ignored files:

| File | What it holds |
|---|---|
| `sos_system/android/app/google-services.json` | Firebase project config (downloaded from Firebase console) |
| `sos_system/secrets.json` | `MAPS_API_KEY` (read by Gradle for the map, and by Dart for Directions/Places calls) |

---

## 1. Firebase project (free Spark plan)

1. https://console.firebase.google.com → **Add project** (Google Analytics optional).
2. **Add app → Android**
   - Package name: `com.kislay.travelguard`
   - Download `google-services.json` → put it in `sos_system/android/app/`
3. **Build → Authentication → Get started → Sign-in method → Email/Password → Enable**
4. **Build → Firestore Database → Create database**
   - Location: `asia-south1 (Mumbai)`
   - Start in **production mode**
   - **Rules** tab → paste the contents of `sos_system/firestore.rules` → **Publish**
5. Cloud Storage is **not** needed (the app doesn't use it, and new Storage buckets require the Blaze plan).

## 2. Google Maps key (same project)

Your Firebase project is also a Google Cloud project. Open https://console.cloud.google.com and select it.

1. **Billing** → link a billing account. Google requires this even for free usage; nothing is charged while you stay under the free caps.
2. **APIs & Services → Library** → enable:
   - Maps SDK for Android
   - Directions API (if it isn't offered for new projects, enable **Routes API**; the app will be migrated to it)
   - Places API (New), for search suggestions
3. **APIs & Services → Credentials → Create credentials → API key**
   - **Edit key → API restrictions → Restrict key** → tick only the APIs above → Save
4. Protect yourself from surprise bills:
   - **Billing → Budgets & alerts** → budget ₹100, alerts at 50 / 90 / 100 %
   - **APIs & Services → (each API) → Quotas** → cap requests per day (e.g. Directions 300/day, Places Autocomplete 300/day) so usage can never pass the free tier

## 3. Local secrets file

```powershell
cd sos_system
Copy-Item secrets.example.json secrets.json
notepad secrets.json   # paste your key
```

```json
{ "MAPS_API_KEY": "AIza...your key..." }
```

## 4. Run

```powershell
cd sos_system
flutter clean
flutter pub get
flutter run --dart-define-from-file=secrets.json
```

In VS Code, **F5** already passes `--dart-define-from-file=secrets.json` (see `.vscode/launch.json`).

If the map is blank → `secrets.json` missing or Maps SDK for Android not enabled.
If "Start Journey" says `REQUEST_DENIED` → Directions API not enabled / not allowed on the key.
