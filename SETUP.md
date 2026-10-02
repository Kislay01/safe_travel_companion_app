# Setup: use your own Firebase + Google Maps keys

No keys are committed. You supply two git-ignored files:

| File | What it holds |
|---|---|
| `sos_system/android/app/google-services.json` | Firebase project config (downloaded from Firebase console) |
| `sos_system/secrets.json` | `MAPS_API_KEY` (read by Gradle for the map, and by Dart for Routes/Places calls) |

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

## 2. Google Maps key (separate Cloud project)

Keep billing **off** the Firebase project so Firebase stays on the free Spark plan.
Create the Maps key in its own Google Cloud project instead.

1. https://console.cloud.google.com → project picker → **New project** `travelguard-maps`
2. **Billing** → link a billing account to **travelguard-maps only** (required even for free usage)
3. **APIs & Services → Library** → enable:
   - Maps SDK for Android
   - Routes API (the legacy Directions API is not available to new projects)
   - Places API (New)
4. **APIs & Services → Credentials → Create credentials → API key**
   - Restriction type: **API restriction** → tick the 3 APIs above
   - (Not "Android apps": the Routes/Places calls are made over HTTP from Dart)
5. Cost guards:
   - Quotas (per minute): Routes *Compute Routes* 30, Places *Autocomplete* 60, Places *Get Place* 30
     (`/apis/api/routes.googleapis.com/quotas`, `/apis/api/places.googleapis.com/quotas`)
   - **Billing → Budgets & alerts** → ₹100, alerts at 50 / 90 / 100 %

Free monthly caps: Maps SDK for Android unlimited, Routes 10k, Places 10k.

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
If "Start Journey" shows a route error → Routes API not enabled or not ticked on the key.
