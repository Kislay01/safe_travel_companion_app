/// Build-time configuration. Values come from `secrets.json` via
/// `flutter run --dart-define-from-file=secrets.json` (see SETUP.md).
class AppConfig {
  AppConfig._();

  /// Google Maps Platform key (Directions / Routes / Places web-service calls).
  static const String mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

  static bool get hasMapsKey => mapsApiKey.isNotEmpty;
}
