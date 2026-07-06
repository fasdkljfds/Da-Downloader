import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper/main.dart';

class FakeCliService implements CliService {
  FakeCliService({this.result});

  CliRunResult? result;
  List<String>? lastArgs;
  bool cancelled = false;

  @override
  bool get isRunning => false;

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<CliRunResult> run(
    List<String> args, {
    required String workingDirectory,
    required void Function(String line) onLog,
  }) async {
    lastArgs = args;
    onLog('fake log');
    await Future<void>.delayed(Duration.zero);
    return result ??
        const CliRunResult(
          exitCode: 0,
          stdout:
              '{"requested":1,"downloaded":1,"skipped":0,"failed":0,"files":[],"errors":[]}',
          logs: ['fake log'],
          json: {
            'requested': 1,
            'downloaded': 1,
            'skipped': 0,
            'failed': 0,
            'files': [],
            'errors': [],
          },
        );
  }
}

void main() {
  Future<void> pumpAppFrame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 30; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
  }

  testWidgets('renders empty gallery and controls', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('wallpaper_empty_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    await tester.pumpWidget(
      DaDownloaderApp(
        cliService: FakeCliService(),
        initialRepoRoot: tempDir.path,
        initialSaveDir: tempDir.path,
        autoRefresh: false,
      ),
    );
    await pumpAppFrame(tester);

    expect(find.text('Da Downloader'), findsOneWidget);
    expect(find.text('图库为空'), findsOneWidget);
    expect(find.text('更新收藏'), findsOneWidget);
    expect(find.text('任务结果'), findsOneWidget);
  });

  testWidgets('runs update through injected cli service', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('wallpaper_job_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final service = FakeCliService();

    await tester.pumpWidget(
      DaDownloaderApp(
        cliService: service,
        initialRepoRoot: tempDir.path,
        initialSaveDir: tempDir.path,
        autoRefresh: false,
        refreshAfterJob: false,
      ),
    );
    await pumpAppFrame(tester);
    expect(find.text('图库为空'), findsOneWidget);

    await tester.tap(find.text('更新收藏'));
    await pumpAppFrame(tester);
    await pumpUntilFound(tester, find.text('fake log'));

    expect(service.lastArgs, isNotNull);
    expect(service.lastArgs, contains('update'));
    expect(find.text('下载 1'), findsOneWidget);
    expect(find.text('fake log'), findsOneWidget);
  });

  testWidgets('renders local image files in gallery', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('wallpaper_images_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final image = File('${tempDir.path}${Platform.pathSeparator}sample.png');
    image.writeAsBytesSync(base64Decode(_transparentPng));

    await tester.pumpWidget(
      DaDownloaderApp(
        cliService: FakeCliService(),
        initialRepoRoot: tempDir.path,
        initialSaveDir: tempDir.path,
        initialImageFiles: [image],
        autoRefresh: false,
      ),
    );
    await pumpAppFrame(tester);

    expect(find.byType(Image), findsWidgets);
    expect(find.textContaining('1 张'), findsOneWidget);
  });
}

const _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
