import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper/hidden_wallpapers.dart';
import 'package:wallpaper/main.dart';

void main() {
  Future<List<File>> createImages(
    WidgetTester tester,
    Directory dir, {
    int count = 1,
    int width = 640,
    int height = 360,
  }) async {
    return (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFF559988), BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return List.generate(count, (i) {
        final file = File('${dir.path}/sample-$i.png');
        file.writeAsBytesSync(data!.buffer.asUint8List());
        return file;
      });
    }))!;
  }

  Future<void> settleImages(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final images = tester.widgetList<RawImage>(find.byType(RawImage));
      if (images.isNotEmpty && images.every((raw) => raw.image != null)) break;
    }
    await tester.pumpAndSettle();
  }

  void cleanUp(WidgetTester tester, Directory dir) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await dir.delete(recursive: true);
      });
    });
  }

  Future<void> waitForHidden(
    WidgetTester tester,
    Directory dir,
    bool hidden,
  ) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (HiddenWallpapers(dir.path).load().isNotEmpty == hidden &&
          find.byType(Image).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
  }

  Future<void> openPreview(WidgetTester tester, Finder tile) async {
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  testWidgets(
    '4K thumbnails retain decoded images and scroll position after preview',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('wallpaper_cache_');
      cleanUp(tester, dir);
      final files = await createImages(
        tester,
        dir,
        count: 40,
        width: 3840,
        height: 2160,
      );
      await tester.pumpWidget(
        DaDownloaderApp(
          initialSaveDir: dir.path,
          initialImageFiles: files,
          autoRefresh: false,
        ),
      );
      await settleImages(tester);
      final grid = find.byType(GridView);
      await tester.drag(grid, const Offset(0, -400));
      await settleImages(tester);
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: grid, matching: find.byType(Scrollable)),
      );
      final offset = scroll.position.pixels;
      final rawFinder = find.descendant(
        of: grid,
        matching: find.byType(RawImage),
      );
      final images = tester
          .widgetList<RawImage>(rawFinder)
          .map((raw) => raw.image)
          .whereType<ui.Image>()
          .toList();
      expect(images, isNotEmpty);
      expect(images.every((image) => image.width == 512), isTrue);
      final bytes = images.fold<int>(
        0,
        (n, image) => n + image.width * image.height * 4,
      );

      // Simulate cache pressure from opening large images. Live thumbnails must
      // remain attached even when the LRU no longer contains them.
      PaintingBinding.instance.imageCache.clear();
      final tile = find
          .descendant(of: grid, matching: find.byType(Image))
          .hitTestable()
          .first;
      final element = tester.element(tile);
      final state = tester.state(tile);
      await openPreview(tester, tile);
      await settleImages(tester);
      expect(find.byType(WallpaperPreviewPage), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(tester.element(tile), same(element));
      expect(tester.state(tile), same(state));
      expect(scroll.position.pixels, offset);
      final returned = tester
          .widgetList<RawImage>(rawFinder)
          .map((raw) => raw.image)
          .whereType<ui.Image>()
          .toList();
      expect(returned.length, images.length);
      for (var i = 0; i < images.length; i++) {
        expect(returned[i], same(images[i]));
      }
      // Also exercise Escape on another round trip.
      await openPreview(tester, tile);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(WallpaperPreviewPage), findsNothing);
      // ignore: avoid_print
      print(
        '4K gallery: ${images.length} decoded thumbnails, $bytes bytes; '
        'original-sized equivalent: ${images.length * 3840 * 2160 * 4} bytes; '
        'preview return: 0 replaced thumbnail images, scroll offset $offset',
      );
    },
  );

  testWidgets('hide from preview persists across restart and can be restored', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('wallpaper_hidden_');
    cleanUp(tester, dir);
    final files = await createImages(tester, dir);
    Widget app() => DaDownloaderApp(
      initialSaveDir: dir.path,
      initialImageFiles: files,
      autoRefresh: false,
    );
    await tester.pumpWidget(app());
    await settleImages(tester);
    await openPreview(tester, find.byType(Image).first);
    await tester.tap(find.byTooltip('隐藏这张壁纸'));
    await waitForHidden(tester, dir, true);
    expect(find.byType(WallpaperPreviewPage), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(files.single.existsSync(), isTrue);
    expect(HiddenWallpapers(dir.path).load(), isNotEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.byTooltip('查看已隐藏'));
    await settleImages(tester);
    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('恢复显示'));
    await waitForHidden(tester, dir, false);
    expect(HiddenWallpapers(dir.path).load(), isEmpty);
    await tester.tap(find.byTooltip('返回图库'));
    await settleImages(tester);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('selection is immediate and ignores dragging', (tester) async {
    final dir = Directory.systemTemp.createTempSync('wallpaper_selection_');
    cleanUp(tester, dir);
    final files = await createImages(tester, dir, count: 16);
    await tester.pumpWidget(
      DaDownloaderApp(
        initialSaveDir: dir.path,
        initialImageFiles: files,
        autoRefresh: false,
      ),
    );
    await settleImages(tester);
    final tile = find.byType(Image).first;
    await tester.tap(tile);
    // One frame, without advancing through a double-tap timeout or animation.
    await tester.pump();
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byType(WallpaperPreviewPage), findsNothing);
    await tester.tap(find.byTooltip('多选壁纸'));
    await tester.pump();
    expect(find.text('已选择 0 张'), findsOneWidget);
    await tester.drag(find.byType(Image).first, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('已选择 0 张'), findsOneWidget);
  });

  testWidgets(
    'multi selection supports toggle, Ctrl, Shift, bulk hide and restore',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('wallpaper_batch_');
      cleanUp(tester, dir);
      final files = await createImages(tester, dir, count: 3);
      Widget app() => DaDownloaderApp(
        initialSaveDir: dir.path,
        initialImageFiles: files,
        autoRefresh: false,
      );
      await tester.pumpWidget(app());
      await settleImages(tester);
      await tester.tap(find.byType(Image).at(0));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byType(Image).at(1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(find.text('已选择 2 张'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byType(Image).at(2));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      // Shift replaces selection with the range from the last clicked image.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      await tester.tap(find.byTooltip('多选壁纸'));
      await tester.pump();
      await tester.tap(find.byType(Image).at(0));
      await tester.pump();
      await tester.tap(find.byType(Image).at(1));
      await tester.pump();
      expect(find.text('已选择 2 张'), findsOneWidget);
      // A second click toggles one image, after the double-tap interval.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(Image).at(0));
      await tester.pump();
      expect(find.text('已选择 1 张'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byType(Image).at(0));
      await tester.pump();
      expect(find.text('已选择 2 张'), findsOneWidget);
      await tester.tap(find.byTooltip('隐藏所选壁纸'));
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (HiddenWallpapers(dir.path).load().length == 2 &&
            find.text('已选择 0 张').evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(HiddenWallpapers(dir.path).load().length, 2);
      expect(find.byType(Image), findsOneWidget);
      expect(files.every((file) => file.existsSync()), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      await settleImages(tester);
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byTooltip('查看已隐藏'));
      await settleImages(tester);
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(Image).hitTestable(), findsNWidgets(2));
      await tester.tap(find.byTooltip('多选壁纸'));
      await tester.pump();
      await tester.tap(find.byTooltip('全选'));
      await tester.pump();
      expect(find.text('已选择 2 张'), findsOneWidget);
      await tester.tap(find.byTooltip('恢复显示'));
      await waitForHidden(tester, dir, false);
      expect(HiddenWallpapers(dir.path).load(), isEmpty);
      await tester.tap(find.byTooltip('返回图库'));
      await settleImages(tester);
      expect(find.byType(Image), findsNWidgets(3));
    },
  );

  test('malformed hidden records are not silently overwritten', () {
    final dir = Directory.systemTemp.createTempSync('wallpaper_bad_hidden_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = HiddenWallpapers(dir.path);
    store.file.writeAsStringSync('{invalid');
    expect(store.load, throwsFormatException);
    expect(store.file.readAsStringSync(), '{invalid');
  });
}
