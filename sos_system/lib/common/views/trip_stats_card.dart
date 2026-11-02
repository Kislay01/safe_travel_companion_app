import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/services/trip_stats.dart';

/// "This month" tiles: journeys, km, reached safely, plus the safe-arrival streak.
class TripStatsCard extends StatefulWidget {
  final String childEmail;

  /// Guardian view: no card background (sits inside another sheet).
  final bool flat;
  const TripStatsCard({super.key, required this.childEmail, this.flat = false});

  @override
  State<TripStatsCard> createState() => _TripStatsCardState();
}

class _TripStatsCardState extends State<TripStatsCard> {
  Future<TripStats>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TripStatsCard old) {
    super.didUpdateWidget(old);
    if (old.childEmail != widget.childEmail) _load();
  }

  void _load() {
    _future = widget.childEmail.isEmpty ? Future.value(const TripStats()) : TripStats.load(widget.childEmail);
  }

  /// Pull-to-refresh hook for parents.
  void refresh() => setState(_load);

  @override
  Widget build(BuildContext context) {
    final muted = TG.mutedOf(context);
    final body = FutureBuilder<TripStats>(
      future: _future,
      builder: (context, snap) {
        final s = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        String v(String Function(TripStats) f) => s == null ? (loading ? '–' : '0') : f(s);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Last 30 days', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                if (s != null && s.sos > 0)
                  Text('${s.sos} SOS', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: TG.sos)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _tile(context, v((s) => '${s.trips}'), 'journeys'),
                const SizedBox(width: 8),
                _tile(context, v((s) => s.km >= 100 ? s.km.round().toString() : s.km.toStringAsFixed(1)), 'km travelled'),
                const SizedBox(width: 8),
                _tile(context, v((s) => '${s.arrived}'), 'reached safely'),
              ],
            ),
            if (s != null && s.streak >= 2) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, size: 18, color: TG.warn),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${s.streak} safe arrivals in a row',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: TG.inkOf(context))),
                  ),
                ],
              ),
            ] else if (s != null && s.trips == 0) ...[
              const SizedBox(height: 8),
              Text('Start a journey and your trips will show up here.', style: TextStyle(fontSize: 12.5, color: muted)),
            ],
          ],
        );
      },
    );
    if (widget.flat) return body;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TG.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: TG.isDark(context)
            ? null
            : [BoxShadow(color: TG.ink.withValues(alpha: 0.06), blurRadius: 2, offset: const Offset(0, 1))],
      ),
      child: body,
    );
  }

  Widget _tile(BuildContext context, String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: TG.softOf(context), borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Text(value,
                  style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: TG.accentTextOf(context))),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: TG.mutedOf(context), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}
