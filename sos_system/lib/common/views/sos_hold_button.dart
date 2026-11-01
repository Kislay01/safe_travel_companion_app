import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sos_system/core/app_theme.dart';
import 'package:sos_system/services/sos_service.dart';

/// Round press-and-hold SOS button. A ring fills while held; on completion the
/// normal SOS pipeline runs (alert every guardian + call the primary contact).
/// A short tap only explains how to use it, so it can't fire by accident.
class SosHoldButton extends StatefulWidget {
  final double size;
  final Duration hold;
  final bool showRings;
  final String hint;

  const SosHoldButton({
    super.key,
    this.size = 160,
    this.hold = const Duration(seconds: 2),
    this.showRings = true,
    this.hint = 'Press and hold',
  });

  @override
  State<SosHoldButton> createState() => _SosHoldButtonState();
}

class _SosHoldButtonState extends State<SosHoldButton> {
  static const _tick = Duration(milliseconds: 40);
  Timer? _timer;
  double _progress = 0;
  bool _sending = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_sending) return;
    HapticFeedback.mediumImpact();
    _timer?.cancel();
    final steps = widget.hold.inMilliseconds / _tick.inMilliseconds;
    var n = 0;
    _timer = Timer.periodic(_tick, (t) {
      n++;
      final p = (n / steps).clamp(0.0, 1.0);
      if (mounted) setState(() => _progress = p);
      if (p >= 1.0) {
        t.cancel();
        _fire();
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    if (!_sending && mounted) setState(() => _progress = 0);
  }

  Future<void> _fire() async {
    setState(() => _sending = true);
    HapticFeedback.heavyImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('SOS sent. Alerting your guardians…')));
    final msg = await SosService.trigger(source: 'button');
    messenger.showSnackBar(SnackBar(content: Text(msg)));
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _progress = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final button = Semantics(
      button: true,
      label: 'SOS. Press and hold to alert your guardians',
      child: GestureDetector(
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Press and hold SOS to alert your guardians')),
        ),
        onLongPressStart: (_) => _start(),
        onLongPressEnd: (_) => _cancel(),
        onLongPressCancel: _cancel,
        child: SizedBox(
          width: s,
          height: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _sending ? TG.sosDark : TG.sos,
                  boxShadow: [
                    BoxShadow(color: TG.sos.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
              ),
              SizedBox(
                width: s - 10,
                height: s - 10,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: s > 100 ? 6 : 4,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sending ? 'SENT' : 'SOS',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontSize: s * 0.26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  if (s > 100 && widget.hint.isNotEmpty)
                    Text(
                      widget.hint,
                      style: GoogleFonts.manrope(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.showRings) return button;
    return Container(
      width: s * 1.45,
      height: s * 1.45,
      decoration: BoxDecoration(shape: BoxShape.circle, color: TG.sos.withValues(alpha: 0.07)),
      alignment: Alignment.center,
      child: Container(
        width: s * 1.22,
        height: s * 1.22,
        decoration: BoxDecoration(shape: BoxShape.circle, color: TG.sos.withValues(alpha: 0.13)),
        alignment: Alignment.center,
        child: button,
      ),
    );
  }
}
