import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A portrait-shaped PNG, painted at runtime.
///
/// Image-editing entries need real encoded bytes. Painting them keeps the
/// catalog offline and free of binary assets, and the gradient and off-centre
/// disc make it obvious when a crop or pan has moved the image.
Future<Uint8List> samplePortraitPng() => _cached ??= _paint();

Future<Uint8List>? _cached;

Future<Uint8List> _paint() async {
  const size = Size(640, 800);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Offset.zero & size);

  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        size.bottomRight(Offset.zero),
        [const Color(0xFF3F51B5), const Color(0xFFFF4081)],
      ),
  );
  canvas.drawCircle(
    const Offset(260, 320),
    170,
    Paint()..color = const Color(0xCCFFFFFF),
  );
  canvas.drawCircle(
    const Offset(260, 320),
    90,
    Paint()..color = const Color(0xFF0F1020),
  );

  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}
