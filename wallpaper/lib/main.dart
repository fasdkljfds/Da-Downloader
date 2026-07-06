import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const DaDownloaderApp());
}

const _defaultSiteUrl =
    'https://wallhaven.cc/user/sjjfirk/favorites/2119257?purity=110&page=';
const _imageExtensions = {'.jpg', '.jpeg', '.png'};

const _ink = Color(0xFF07090C);
const _surface = Color(0xFF101318);
const _surfaceHigh = Color(0xFF171B22);
const _line = Color(0xFF262C36);
const _accent = Color(0xFF79C7C5);
const _text = Color(0xFFE9EEF4);
const _muted = Color(0xFF8C95A3);
const _danger = Color(0xFFE56B6F);

String _joinPath(String a, String b, [String? c]) {
  final sep = Platform.pathSeparator;
  final first = a.endsWith(sep) ? a.substring(0, a.length - 1) : a;
  final second = b.startsWith(sep) ? b.substring(1) : b;
  if (c == null) {
    return '$first$sep$second';
  }
  return _joinPath('$first$sep$second', c);
}

bool _isRepoRoot(Directory directory) {
  return File(_joinPath(directory.path, 'library.py')).existsSync() &&
      Directory(_joinPath(directory.path, 'cli')).existsSync();
}

String? _findRepoRootFrom(Directory start) {
  var current = start.absolute;
  while (true) {
    if (_isRepoRoot(current)) {
      return current.path;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

String _detectRepoRoot() {
  final starts = <Directory>[Directory.current];
  final executable = Platform.resolvedExecutable;
  if (executable.isNotEmpty) {
    starts.add(File(executable).parent);
  }

  for (final start in starts) {
    final repoRoot = _findRepoRootFrom(start);
    if (repoRoot != null) {
      return repoRoot;
    }
  }

  return Directory.current.path;
}

String _defaultSaveDir(String repoRoot) {
  return r'F:\estore\wallpaper';
}

abstract class CliService {
  bool get isRunning;

  Future<CliRunResult> run(
    List<String> args, {
    required String workingDirectory,
    required void Function(String line) onLog,
  });

  Future<void> cancel();
}

class CliRunResult {
  const CliRunResult({
    required this.exitCode,
    required this.stdout,
    required this.logs,
    required this.json,
  });

  final int exitCode;
  final String stdout;
  final List<String> logs;
  final Map<String, dynamic>? json;

  bool get succeeded => exitCode == 0;
}

class PythonCliService implements CliService {
  Process? _process;

  @override
  bool get isRunning => _process != null;

  @override
  Future<CliRunResult> run(
    List<String> args, {
    required String workingDirectory,
    required void Function(String line) onLog,
  }) async {
    if (_process != null) {
      throw StateError('已有任务正在运行');
    }

    final stdoutBuffer = StringBuffer();
    final logs = <String>[];
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    try {
      final process = await Process.start(
        'py',
        args,
        workingDirectory: workingDirectory,
      );
      _process = process;

      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => stdoutBuffer.writeln(line),
            onDone: stdoutDone.complete,
            onError: stdoutDone.completeError,
          );

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              logs.add(line);
              onLog(line);
            },
            onDone: stderrDone.complete,
            onError: stderrDone.completeError,
          );

      final exitCode = await process.exitCode;
      await Future.wait([stdoutDone.future, stderrDone.future]);
      final stdout = stdoutBuffer.toString().trim();

      return CliRunResult(
        exitCode: exitCode,
        stdout: stdout,
        logs: logs,
        json: _decodeJson(stdout),
      );
    } on ProcessException catch (error) {
      final message = '无法启动 py.exe: ${error.message}';
      onLog(message);
      return CliRunResult(
        exitCode: -1,
        stdout: '',
        logs: [message],
        json: null,
      );
    } finally {
      _process = null;
    }
  }

  @override
  Future<void> cancel() async {
    _process?.kill();
  }

  Map<String, dynamic>? _decodeJson(String stdout) {
    if (stdout.isEmpty) {
      return null;
    }
    final lines = stdout
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty);
    if (lines.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(lines.last);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class DaDownloaderApp extends StatelessWidget {
  const DaDownloaderApp({
    super.key,
    this.cliService,
    this.initialRepoRoot,
    this.initialSaveDir,
    this.initialImageFiles,
    this.autoRefresh = true,
    this.refreshAfterJob = true,
  });

  final CliService? cliService;
  final String? initialRepoRoot;
  final String? initialSaveDir;
  final List<File>? initialImageFiles;
  final bool autoRefresh;
  final bool refreshAfterJob;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Da Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent,
          surface: _surface,
          error: _danger,
        ),
        textSelectionTheme: const TextSelectionThemeData(cursorColor: _accent),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _text,
          contentTextStyle: const TextStyle(color: _ink),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: WallpaperHomePage(
        cliService: cliService ?? PythonCliService(),
        initialRepoRoot: initialRepoRoot,
        initialSaveDir: initialSaveDir,
        initialImageFiles: initialImageFiles,
        autoRefresh: autoRefresh,
        refreshAfterJob: refreshAfterJob,
      ),
    );
  }
}

class WallpaperHomePage extends StatefulWidget {
  const WallpaperHomePage({
    super.key,
    required this.cliService,
    this.initialRepoRoot,
    this.initialSaveDir,
    this.initialImageFiles,
    this.autoRefresh = true,
    this.refreshAfterJob = true,
  });

  final CliService cliService;
  final String? initialRepoRoot;
  final String? initialSaveDir;
  final List<File>? initialImageFiles;
  final bool autoRefresh;
  final bool refreshAfterJob;

  @override
  State<WallpaperHomePage> createState() => _WallpaperHomePageState();
}

class _WallpaperHomePageState extends State<WallpaperHomePage> {
  late final TextEditingController _saveDirController;
  late final TextEditingController _siteUrlController;
  late final TextEditingController _cookieController;
  late final TextEditingController _refererController;
  late final TextEditingController _extensionsController;
  late final TextEditingController _pageRangeController;
  late final TextEditingController _imageController;
  late final TextEditingController _startPageController;
  late final TextEditingController _maxPagesController;
  late final ScrollController _logController;
  late final String _repoRoot;

  final List<File> _imageFiles = [];
  final List<String> _logs = [];
  File? _selectedFile;
  Map<String, dynamic>? _lastPayload;
  bool _isLoading = false;
  bool _isRunning = false;
  bool _force = false;
  String _status = '就绪';
  double _gridItemWidth = 260;

  @override
  void initState() {
    super.initState();
    _repoRoot = widget.initialRepoRoot ?? _detectRepoRoot();
    _saveDirController = TextEditingController(
      text: widget.initialSaveDir ?? _defaultSaveDir(_repoRoot),
    );
    _siteUrlController = TextEditingController(text: _defaultSiteUrl);
    _cookieController = TextEditingController();
    _refererController = TextEditingController();
    _extensionsController = TextEditingController(text: 'jpg,png,jpeg');
    _pageRangeController = TextEditingController(text: '1');
    _imageController = TextEditingController();
    _startPageController = TextEditingController(text: '1');
    _maxPagesController = TextEditingController(text: '3');
    _logController = ScrollController();
    _imageFiles.addAll(widget.initialImageFiles ?? []);
    if (_imageFiles.isNotEmpty) {
      _status = '已载入 ${_imageFiles.length} 张';
    }

    if (widget.autoRefresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshLibrary();
      });
    }
  }

  @override
  void dispose() {
    _saveDirController.dispose();
    _siteUrlController.dispose();
    _cookieController.dispose();
    _refererController.dispose();
    _extensionsController.dispose();
    _pageRangeController.dispose();
    _imageController.dispose();
    _startPageController.dispose();
    _maxPagesController.dispose();
    _logController.dispose();
    widget.cliService.cancel();
    super.dispose();
  }

  String get _saveDir => _saveDirController.text.trim();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _ControlRail(
              isRunning: _isRunning,
              force: _force,
              saveDirController: _saveDirController,
              siteUrlController: _siteUrlController,
              cookieController: _cookieController,
              refererController: _refererController,
              extensionsController: _extensionsController,
              pageRangeController: _pageRangeController,
              imageController: _imageController,
              startPageController: _startPageController,
              maxPagesController: _maxPagesController,
              onForceChanged: (value) => setState(() => _force = value),
              onPickFolder: _pickFolder,
              onRefresh: _refreshLibrary,
              onOpenFolder: () => _openFolder(_saveDir),
              onUpdate: _runUpdate,
              onDownloadPages: _runDownloadPages,
              onDownloadImage: _runDownloadImage,
              onRetry: _runRetry,
              onCancel: _cancelJob,
            ),
            Expanded(
              child: Column(
                children: [
                  _GalleryHeader(
                    count: _imageFiles.length,
                    selectedFile: _selectedFile,
                    status: _status,
                    isRunning: _isRunning,
                    onRefresh: _refreshLibrary,
                    onOpenSelected: _selectedFile == null
                        ? null
                        : () => _openFile(_selectedFile!),
                    onOpenSelectedFolder: _selectedFile == null
                        ? null
                        : () => _openFolder(_selectedFile!.parent.path),
                    onSetWallpaper: _selectedFile == null
                        ? null
                        : () => _setWallpaper(_selectedFile!),
                  ),
                  Expanded(child: _buildGallery()),
                  _JobConsole(
                    payload: _lastPayload,
                    logs: _logs,
                    controller: _logController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGallery() {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            HardwareKeyboard.instance.isControlPressed) {
          setState(() {
            _gridItemWidth += event.scrollDelta.dy < 0 ? 20 : -20;
            _gridItemWidth = _gridItemWidth.clamp(160, 420);
          });
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _imageFiles.isEmpty
            ? _EmptyGallery(onPickFolder: _pickFolder, onUpdate: _runUpdate)
            : GridView.builder(
                key: const ValueKey('gallery-grid'),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: _gridItemWidth,
                  childAspectRatio: 0.68,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                ),
                itemCount: _imageFiles.length,
                itemBuilder: (context, index) {
                  final file = _imageFiles[index];
                  return _WallpaperTile(
                    file: file,
                    selected: file.path == _selectedFile?.path,
                    onSelected: () => setState(() => _selectedFile = file),
                    onOpenPreview: () => _openPreview(file),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _pickFolder() async {
    final selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory == null) {
      return;
    }
    _saveDirController.text = selectedDirectory;
    if (widget.refreshAfterJob) {
      await _refreshLibrary();
    }
  }

  Future<void> _refreshLibrary() async {
    setState(() {
      _isLoading = true;
      _status = '刷新图库';
    });

    try {
      final directory = Directory(_saveDir);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      final files = <File>[];
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File && _isImageFile(entity.path)) {
          files.add(entity);
        }
      }
      files.sort((a, b) {
        final bTime = b.lastModifiedSync();
        final aTime = a.lastModifiedSync();
        return bTime.compareTo(aTime);
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _imageFiles
          ..clear()
          ..addAll(files);
        if (_selectedFile != null &&
            !_imageFiles.any((file) => file.path == _selectedFile!.path)) {
          _selectedFile = null;
        }
        _status = '已载入 ${files.length} 张';
      });
    } catch (error) {
      _appendLog('刷新失败: $error');
      if (mounted) {
        setState(() => _status = '刷新失败');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any(lower.endsWith);
  }

  Future<void> _runUpdate() async {
    final args = [
      'update',
      ..._commonArgs(),
      '--start-page',
      _startPageController.text.trim().isEmpty
          ? '1'
          : _startPageController.text.trim(),
    ];
    final maxPages = _maxPagesController.text.trim();
    if (maxPages.isNotEmpty) {
      args.addAll(['--max-pages', maxPages]);
    }

    args.add('--no-stop-when-known');

    await _runWallhavenJob('更新收藏', args);
  }

  Future<void> _runDownloadPages() async {
    final pages = _pageRangeController.text.trim();
    if (pages.isEmpty) {
      _showSnack('请输入页码');
      return;
    }
    await _runWallhavenJob('下载页面', ['page', ..._commonArgs(), pages]);
  }

  Future<void> _runDownloadImage() async {
    final image = _imageController.text.trim();
    if (image.isEmpty) {
      _showSnack('请输入图片 ID 或链接');
      return;
    }
    await _runWallhavenJob('下载单图', ['image', ..._commonArgs(), image]);
  }

  Future<void> _runRetry() async {
    await _runWallhavenJob('重试失败', ['retry', ..._commonArgs()]);
  }

  Future<void> _runWallhavenJob(
    String title,
    List<String> wallhavenArgs,
  ) async {
    if (_isRunning) {
      return;
    }

    final args = [
      '-B',
      '-m',
      'cli.cli_main',
      '--json',
      'wallhaven',
      ...wallhavenArgs,
    ];
    setState(() {
      _isRunning = true;
      _status = '$title 运行中';
      _lastPayload = null;
    });
    _appendLog('工作目录: $_repoRoot');
    _appendLog('> py ${args.join(' ')}');

    final result = await widget.cliService.run(
      args,
      workingDirectory: _repoRoot,
      onLog: _appendLog,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isRunning = false;
      _lastPayload = result.json;
      _status = result.succeeded ? '$title 完成' : '$title 失败';
    });

    if (result.stdout.isNotEmpty && result.json == null) {
      _appendLog(result.stdout);
    }
    if (!result.succeeded) {
      _showSnack('$title 失败');
    }

    await _refreshLibrary();
  }

  List<String> _commonArgs() {
    final args = [
      '--save-dir',
      _saveDir,
      '--site-url',
      _siteUrlController.text.trim(),
      '--extensions',
      _extensionsController.text.trim().isEmpty
          ? 'jpg,png,jpeg'
          : _extensionsController.text.trim(),
      '--timeout',
      '15',
      '--tries',
      '3',
    ];

    final cookie = _cookieController.text.trim();
    if (cookie.isNotEmpty) {
      args.addAll(['--cookie', cookie]);
    }

    final referer = _refererController.text.trim();
    if (referer.isNotEmpty) {
      args.addAll(['--referer', referer]);
    }

    if (_force) {
      args.add('--force');
    }

    return args;
  }

  Future<void> _cancelJob() async {
    await widget.cliService.cancel();
    if (mounted) {
      setState(() {
        _isRunning = false;
        _status = '已取消';
      });
      _appendLog('任务已取消');
    }
  }

  void _appendLog(String line) {
    if (!mounted || line.trim().isEmpty) {
      return;
    }
    setState(() {
      _logs.add(line);
      if (_logs.length > 160) {
        _logs.removeRange(0, _logs.length - 160);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logController.hasClients) {
        _logController.animateTo(
          _logController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openPreview(File file) async {
    setState(() => _selectedFile = file);
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: WallpaperPreviewPage(imageFile: file),
          );
        },
      ),
    );
  }

  Future<void> _openFolder(String path) async {
    try {
      await Process.run('explorer', [path]);
    } catch (error) {
      _showSnack('无法打开文件夹');
      _appendLog('打开文件夹失败: $error');
    }
  }

  Future<void> _openFile(File file) async {
    try {
      await Process.run('explorer', ['/select,${file.path}']);
    } catch (error) {
      _showSnack('无法打开文件');
      _appendLog('打开文件失败: $error');
    }
  }

  Future<void> _setWallpaper(File file) async {
    try {
      await setWindowsWallpaper(file.path);
      _showSnack('壁纸已更换');
    } catch (error) {
      _showSnack('壁纸更换失败');
      _appendLog('壁纸更换失败: $error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ControlRail extends StatelessWidget {
  const _ControlRail({
    required this.isRunning,
    required this.force,
    required this.saveDirController,
    required this.siteUrlController,
    required this.cookieController,
    required this.refererController,
    required this.extensionsController,
    required this.pageRangeController,
    required this.imageController,
    required this.startPageController,
    required this.maxPagesController,
    required this.onForceChanged,
    required this.onPickFolder,
    required this.onRefresh,
    required this.onOpenFolder,
    required this.onUpdate,
    required this.onDownloadPages,
    required this.onDownloadImage,
    required this.onRetry,
    required this.onCancel,
  });

  final bool isRunning;
  final bool force;
  final TextEditingController saveDirController;
  final TextEditingController siteUrlController;
  final TextEditingController cookieController;
  final TextEditingController refererController;
  final TextEditingController extensionsController;
  final TextEditingController pageRangeController;
  final TextEditingController imageController;
  final TextEditingController startPageController;
  final TextEditingController maxPagesController;
  final ValueChanged<bool> onForceChanged;
  final VoidCallback onPickFolder;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFolder;
  final VoidCallback onUpdate;
  final VoidCallback onDownloadPages;
  final VoidCallback onDownloadImage;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 326,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Da Downloader',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Wallhaven',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('图库'),
            _PathField(
              controller: saveDirController,
              onPickFolder: onPickFolder,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _QuietButton(
                    icon: Icons.refresh_rounded,
                    label: '刷新',
                    onPressed: isRunning ? null : onRefresh,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuietButton(
                    icon: Icons.folder_open_rounded,
                    label: '打开',
                    onPressed: onOpenFolder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionLabel('下载'),
            _AppTextField(controller: siteUrlController, label: '列表地址'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _AppTextField(
                    controller: startPageController,
                    label: '起始页',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AppTextField(
                    controller: maxPagesController,
                    label: '页数',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PrimaryButton(
              icon: Icons.sync_rounded,
              label: isRunning ? '更新中' : '更新收藏',
              onPressed: isRunning ? null : onUpdate,
            ),
            const SizedBox(height: 12),
            _AppTextField(controller: pageRangeController, label: '页码'),
            const SizedBox(height: 8),
            _QuietButton(
              icon: Icons.download_rounded,
              label: '下载页面',
              onPressed: isRunning ? null : onDownloadPages,
            ),
            const SizedBox(height: 12),
            _AppTextField(controller: imageController, label: '图片 ID / 链接'),
            const SizedBox(height: 8),
            _QuietButton(
              icon: Icons.add_photo_alternate_rounded,
              label: '下载单图',
              onPressed: isRunning ? null : onDownloadImage,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _QuietButton(
                    icon: Icons.replay_rounded,
                    label: '重试失败',
                    onPressed: isRunning ? null : onRetry,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DangerButton(
                    icon: Icons.stop_rounded,
                    label: '取消',
                    onPressed: isRunning ? onCancel : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionLabel('请求'),
            _AppTextField(controller: extensionsController, label: '格式'),
            const SizedBox(height: 10),
            _AppTextField(controller: refererController, label: 'Referer'),
            const SizedBox(height: 10),
            _AppTextField(
              controller: cookieController,
              label: 'Cookie',
              obscureText: true,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: force,
              dense: true,
              activeThumbColor: _accent,
              title: const Text('强制下载', style: TextStyle(fontSize: 13)),
              onChanged: isRunning ? null : onForceChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.count,
    required this.selectedFile,
    required this.status,
    required this.isRunning,
    required this.onRefresh,
    required this.onOpenSelected,
    required this.onOpenSelectedFolder,
    required this.onSetWallpaper,
  });

  final int count;
  final File? selectedFile;
  final String status;
  final bool isRunning;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenSelected;
  final VoidCallback? onOpenSelectedFolder;
  final VoidCallback? onSetWallpaper;

  @override
  Widget build(BuildContext context) {
    final selectedName = selectedFile == null
        ? '未选择'
        : selectedFile!.uri.pathSegments.last;

    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: _ink,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count 张 · $status',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isRunning)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            ),
          const SizedBox(width: 10),
          _HeaderIcon(
            icon: Icons.refresh_rounded,
            tooltip: '刷新图库',
            onPressed: onRefresh,
          ),
          _HeaderIcon(
            icon: Icons.image_search_rounded,
            tooltip: '定位文件',
            onPressed: onOpenSelected,
          ),
          _HeaderIcon(
            icon: Icons.folder_open_rounded,
            tooltip: '打开目录',
            onPressed: onOpenSelectedFolder,
          ),
          _HeaderIcon(
            icon: Icons.wallpaper_rounded,
            tooltip: '设为壁纸',
            onPressed: onSetWallpaper,
          ),
        ],
      ),
    );
  }
}

class _WallpaperTile extends StatefulWidget {
  const _WallpaperTile({
    required this.file,
    required this.selected,
    required this.onSelected,
    required this.onOpenPreview,
  });

  final File file;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onOpenPreview;

  @override
  State<_WallpaperTile> createState() => _WallpaperTileState();
}

class _WallpaperTileState extends State<_WallpaperTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showOverlay = _hovered || widget.selected;
    final filename = widget.file.uri.pathSegments.last;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelected,
        onDoubleTap: widget.onOpenPreview,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? _accent
                  : _hovered
                  ? const Color(0xFF48505C)
                  : Colors.transparent,
            ),
          ),
          padding: const EdgeInsets.all(2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: widget.file.path,
                  child: Image.file(
                    widget.file,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const ColoredBox(
                          color: _surfaceHigh,
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: _muted,
                          ),
                        ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: showOverlay ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.74),
                          ],
                        ),
                      ),
                      child: Text(
                        filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: _text),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobConsole extends StatelessWidget {
  const _JobConsole({
    required this.payload,
    required this.logs,
    required this.controller,
  });

  final Map<String, dynamic>? payload;
  final List<String> logs;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
              child: _PayloadSummary(payload: payload),
            ),
          ),
          const VerticalDivider(width: 1, color: _line),
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      return Text(
                        logs[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB7C0CC),
                          fontFamily: 'Consolas',
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PayloadSummary extends StatelessWidget {
  const _PayloadSummary({required this.payload});

  final Map<String, dynamic>? payload;

  @override
  Widget build(BuildContext context) {
    final requested = payload?['requested'] ?? '-';
    final downloaded = payload?['downloaded'] ?? '-';
    final skipped = payload?['skipped'] ?? '-';
    final failed = payload?['failed'] ?? '-';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '任务结果',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Metric(label: '请求', value: '$requested'),
            _Metric(label: '下载', value: '$downloaded'),
            _Metric(label: '跳过', value: '$skipped'),
            _Metric(
              label: '失败',
              value: '$failed',
              danger: failed != '-' && failed != 0,
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: danger ? _danger : _line),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(color: danger ? _danger : _text, fontSize: 12),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({required this.onPickFolder, required this.onUpdate});

  final VoidCallback onPickFolder;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined, color: _muted, size: 50),
            const SizedBox(height: 16),
            const Text(
              '图库为空',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _QuietButton(
                  icon: Icons.folder_open_rounded,
                  label: '选择目录',
                  onPressed: onPickFolder,
                ),
                const SizedBox(width: 10),
                _PrimaryButton(
                  icon: Icons.sync_rounded,
                  label: '更新',
                  onPressed: onUpdate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WallpaperPreviewPage extends StatelessWidget {
  const WallpaperPreviewPage({super.key, required this.imageFile});

  final File imageFile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: imageFile.path,
            child: Image.file(imageFile, fit: BoxFit.contain),
          ),
          Positioned(
            top: 18,
            left: 18,
            child: _PreviewToolbar(
              children: [
                _PreviewIcon(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Positioned(
            right: 18,
            bottom: 18,
            child: _PreviewToolbar(
              children: [
                _PreviewIcon(
                  icon: Icons.image_search_rounded,
                  tooltip: '定位文件',
                  onPressed: () =>
                      Process.run('explorer', ['/select,${imageFile.path}']),
                ),
                _PreviewIcon(
                  icon: Icons.folder_open_rounded,
                  tooltip: '打开目录',
                  onPressed: () =>
                      Process.run('explorer', [imageFile.parent.path]),
                ),
                _PreviewIcon(
                  icon: Icons.wallpaper_rounded,
                  tooltip: '设为壁纸',
                  onPressed: () async {
                    try {
                      await setWindowsWallpaper(imageFile.path);
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('壁纸已更换')));
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('壁纸更换失败')));
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewToolbar extends StatelessWidget {
  const _PreviewToolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      color: _text,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

Future<void> setWindowsWallpaper(String imagePath) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('仅支持 Windows');
  }

  final escapedPath = imagePath.replaceAll("'", "''");
  final script =
      '''
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(
        int uAction,
        int uParam,
        string lpvParam,
        int fuWinIni
    );
}
"@

\$ok = [Wallpaper]::SystemParametersInfo(20, 0, '$escapedPath', 3)
if (-not \$ok) { exit 1 }
''';

  final result = await Process.run('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    script,
  ]);

  if (result.exitCode != 0) {
    final stderr = result.stderr.toString().trim();
    throw Exception(stderr.isEmpty ? 'Windows API 调用失败' : stderr);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({required this.controller, required this.onPickFolder});

  final TextEditingController controller;
  final VoidCallback onPickFolder;

  @override
  Widget build(BuildContext context) {
    return _AppTextField(
      controller: controller,
      label: '保存目录',
      suffix: IconButton(
        tooltip: '选择目录',
        icon: const Icon(Icons.more_horiz_rounded),
        onPressed: onPickFolder,
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    this.suffix,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final Widget? suffix;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(fontSize: 13, color: _text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted, fontSize: 12),
        suffixIcon: suffix,
        filled: true,
        fillColor: _surfaceHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _accent),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: _ink,
        disabledBackgroundColor: _line,
        disabledForegroundColor: _muted,
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _text,
        disabledForegroundColor: _muted,
        minimumSize: const Size(0, 40),
        side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _danger,
        disabledForegroundColor: _muted,
        minimumSize: const Size(0, 40),
        side: const BorderSide(color: _danger),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        color: _text,
        disabledColor: _muted,
        onPressed: onPressed,
      ),
    );
  }
}
