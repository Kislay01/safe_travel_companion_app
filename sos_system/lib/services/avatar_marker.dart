import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:sos_system/core/app_theme.dart';

/// Map pin showing the person's photo (or initial) in a teal ring with a point.
class AvatarMarker {
  AvatarMarker._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// [key] should change when the photo changes (e.g. email + photo length).
  static Future<BitmapDescriptor> build({
    required String key,
    required String name,
    Uint8List? photo,
    Color ring = TG.teal,
  }) async {
    final cacheKey = '$key|${photo?.length ?? 0}|${ring.toARGB32()}';
    final hit = _cache[cacheKey];
    if (hit != null) return hit;

    const size = 132.0; // px; drawn at 3x and shown at 44 logical px wide
    const pointH = 22.0;
    const border = 8.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    final r = size / 2;

    // pointer
    final path = Path()
      ..moveTo(size / 2 - 18, size - 14)
      ..lineTo(size / 2, size + pointH)
      ..lineTo(size / 2 + 18, size - 14)
      ..close();
    canvas.drawPath(path, Paint()..color = ring);
    // ring + white gap
    canvas.drawCircle(center, r, Paint()..color = ring);
    canvas.drawCircle(center, r - border, Paint()..color = Colors.white);
    final inner = r - border - 3;

    if (photo != null) {
      try {
        final codec = await ui.instantiateImageCodec(photo);
        final frame = await codec.getNextFrame();
        final img = frame.image;
        final src = img.width < img.height
            ? Rect.fromLTWH(0, (img.height - img.width) / 2, img.width.toDouble(), img.width.toDouble())
            : Rect.fromLTWH((img.width - img.height) / 2, 0, img.height.toDouble(), img.height.toDouble());
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: inner)));
        canvas.drawImageRect(img, src, Rect.fromCircle(center: center, radius: inner), Paint());
        canvas.restore();
      } catch (_) {
        photo = null;
      }
    }
    if (photo == null) {
      canvas.drawCircle(center, inner, Paint()..color = TG.tealSoft);
      final tp = TextPainter(
        text: TextSpan(
          text: name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w800, color: TG.tealDark),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    final image = await recorder.endRecording().toImage(size.toInt(), (size + pointH).toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.bytes(data!.buffer.asUint8List(), width: 44);
    _cache[cacheKey] = icon;
    return icon;
  }
}
