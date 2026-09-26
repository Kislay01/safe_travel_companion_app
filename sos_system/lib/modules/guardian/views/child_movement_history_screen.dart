import 'package:flutter/material.dart';
import 'package:sos_system/common/views/custom_appbar.dart';

class ChildMovementHistory extends StatefulWidget {
  const ChildMovementHistory({super.key});

  @override
  State<ChildMovementHistory> createState() => _ChildMovementHistoryState();
}

class _ChildMovementHistoryState extends State<ChildMovementHistory> {
  final List<Map<String, String>> _trips = [
    {"title": "Home to Library", "time": "10:00 AM - 11:00 AM"},
    {"title": "Library to Cafe", "time": "11:30 AM - 12:30 PM"},
    {"title": "Cafe to Park", "time": "1:00 PM - 2:00 PM"},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final cardColor = Theme.of(context).cardColor;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final chipBg = isDark ? Colors.grey[850] : Colors.blue.shade50;
    final chipTextColor = isDark ? Colors.white : Colors.blue.shade700;

    return Scaffold(
      appBar: const CustomAppBar(title: "Child Movement History"),
      backgroundColor: pageBg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color:
                              isDark ? Colors.grey.shade800 : Colors.transparent),
                    ),
                    child: Text(
                      'Filter by Date',
                      style: TextStyle(
                          color: chipTextColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Trip list
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: ListView.separated(
                  itemCount: _trips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final trip = _trips[index];
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
                        border: Border.all(
                            color: isDark
                                ? Colors.grey.shade800
                                : Colors.transparent),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.blueGrey[800]
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.place_rounded,
                            color: Color(0xFF2B9AF3),
                          ),
                        ),
                        title: Text(
                          trip['title']!,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: titleColor,
                          ),
                        ),
                        subtitle: Text(
                          trip['time']!,
                          style: TextStyle(
                            color: subtitleColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onTap: () {
                          // Optional: implement navigation to trip details
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
