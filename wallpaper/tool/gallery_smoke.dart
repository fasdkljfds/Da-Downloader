// Native desktop QA with synthetic 4K wallpapers, separate from the real library.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:wallpaper/main.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Preparing synthetic wallpaper library…')),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => _prepareLibrary());
}

Future<void> _prepareLibrary() async {
  final directory = Directory('.test-output/gallery-smoke').absolute;
  await directory.create(recursive: true);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 3840, 2160),
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF193F59), Color(0xFF64B39B)],
      ).createShader(const Rect.fromLTWH(0, 0, 3840, 2160)),
  );
  canvas.drawCircle(
    const Offset(2800, 700),
    320,
    Paint()..color = const Color(0xFFF6DB99),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(3840, 2160);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  image.dispose();
  picture.dispose();
  final files = <File>[];
  for (var i = 0; i < 60; i++) {
    final file = File('${directory.path}/landscape-$i.png');
    if (!file.existsSync()) await file.writeAsBytes(bytes.buffer.asUint8List());
    files.add(file);
  }
  runApp(
    DaDownloaderApp(
      initialSaveDir: directory.path,
      initialImageFiles: files,
      autoRefresh: false,
    ),
  );
}
