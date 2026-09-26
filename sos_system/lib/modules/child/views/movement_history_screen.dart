import 'package:flutter/material.dart';
import 'package:sos_system/common/views/custom_appbar.dart';
import 'package:geocoding/geocoding.dart';
import 'package:location/location.dart' as location;
import 'package:intl/intl.dart'; // ✅ For date formatting

class MovementHistoryScreen extends StatefulWidget {
  const MovementHistoryScreen({super.key});

  // ✅ Static list shared across the session
  static final List<Map<String, String>> _trips = [];

  // ✅ Function to add a trip from JourneyScreen
  static void addTrip(String destination, {String? currentShort}) {
    final now = DateTime.now();
    final formattedTime =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final formattedDate = DateFormat('dd-MM-yyyy').format(now);

    _trips.add({
      "destination": destination,
      "currentShort": currentShort ?? "Unknown Location",
      "time": formattedTime,
      "date": formattedDate,
    });
  }

  @override
  State<MovementHistoryScreen> createState() => _MovementHistoryScreenState();
}

class _MovementHistoryScreenState extends State<MovementHistoryScreen> {
  String? _currentLocationShort;
  final location.Location _location = location.Location();

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocationShort();
  }

  /// ✅ Fetches current location and converts it to short format (Area, City)
  Future<void> _fetchCurrentLocationShort() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    var permission = await _location.hasPermission();
    if (permission == location.PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != location.PermissionStatus.granted) return;
    }

    final loc = await _location.getLocation();
    try {
      final placemarks =
          await placemarkFromCoordinates(loc.latitude!, loc.longitude!);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        setState(() {
          _currentLocationShort =
              "${p.subLocality ?? p.name ?? ""}, ${p.locality ?? p.administrativeArea ?? ""}";
        });
      }
    } catch (e) {
      debugPrint("Error fetching location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = MovementHistoryScreen._trips;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final cardColor = Theme.of(context).cardColor;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[700];

    return Scaffold(
      appBar: const CustomAppBar(title: "Movement History"),
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Current location short (area + city)
            if (_currentLocationShort != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location,
                          color: Colors.blueAccent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Current: $_currentLocationShort",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ✅ List of trips
            Expanded(
              child: trips.isEmpty
                  ? const Center(
                      child: Text(
                        "No journeys yet",
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: trips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final trip = trips[index];
                        final titleText =
                            "${trip['currentShort']} - ${trip['destination']}";
                        return Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              if (!isDark)
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                )
                            ],
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.place_rounded,
                                color: Color(0xFF2B9AF3),
                              ),
                            ),
                            title: Text(
                              titleText,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: titleColor,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              "Date: ${trip['date']} • Time: ${trip['time']}",
                              style: TextStyle(color: subtitleColor),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
