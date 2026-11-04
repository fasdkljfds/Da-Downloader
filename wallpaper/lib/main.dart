import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hidden_wallpapers.dart';

void main() {
  runApp(const DaDownloaderApp());
}

const _imageExtensions = {'.jpg', '.jpeg', '.png'};

const _ink = Color(0xFF11151B);
const _surface = Color(0xFF171D25);
const _surfaceHigh = Color(0xFF202833);
const _line = Color(0xFF2A3441);
const _accent = Color(0xFFA9D8C5);
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
  late final String _saveDir;
  late final ScrollController _logController;
  late final String _repoRoot;
  late final HiddenWallpapers _hiddenStore;
  final Set<String> _hidden = {};
  final _preview = ValueNotifier<File?>(null);
  final _galleryController = ScrollController();
  final _hiddenGalleryController = ScrollController();
  bool _showHidden = false;
  bool _savingHidden = false;
  bool _hiddenLoadFailed = false;
  final Set<String> _selectedPaths = {};
  bool _multiSelect = false;
  String? _selectionAnchor;

  List<File> get _visibleFiles => _imageFiles
      .where(
        (file) => _hidden.contains(_hiddenStore.keyFor(file)) == _showHidden,
      )
      .toList();

  final List<File> _imageFiles = [];
  final List<String> _logs = [];
  File? _selectedFile;
  Map<String, dynamic>? _lastPayload;
  bool _isLoading = false;
  bool _isRunning = false;
  String _status = '就绪';
  double _gridItemWidth = 260;

  @override
  void initState() {
    super.initState();
    _repoRoot = widget.initialRepoRoot ?? _detectRepoRoot();
    _saveDir = widget.initialSaveDir ?? _defaultSaveDir(_repoRoot);
    _hiddenStore = HiddenWallpapers(_saveDir);
    _loadHidden();
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
    _preview.dispose();
    _galleryController.dispose();
    _hiddenGalleryController.dispose();
    _logController.dispose();
    widget.cliService.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_preview.value != null) {
            _closePreview();
          } else {
            setState(() {
              _selectedPaths.clear();
              _selectedFile = null;
              _multiSelect = false;
            });
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: ValueListenableBuilder<File?>(
          valueListenable: _preview,
          child: _buildHome(),
          builder: (context, file, home) => Stack(
            fit: StackFit.expand,
            children: [
              home!,
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: file == null,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    reverseDuration: const Duration(milliseconds: 160),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.96,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: file == null
                        ? null
                        : WallpaperPreviewPage(
                            key: ValueKey(file.path),
                            imageFile: file,
                            onClose: _closePreview,
                            isHidden: _hidden.contains(
                              _hiddenStore.keyFor(file),
                            ),
                            onToggleHidden: () => _toggleHidden(file),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHome() {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _ControlRail(isRunning: _isRunning, onUpdate: _runUpdate),
            Expanded(
              child: Column(
                children: [
                  _GalleryHeader(
                    count: _visibleFiles.length,
                    selectionCount: _selectedPaths.length,
                    multiSelect: _multiSelect,
                    onToggleMultiSelect: () => setState(() {
                      _multiSelect = !_multiSelect;
                      _selectedPaths.clear();
                      _selectedFile = null;
                      _selectionAnchor = null;
                    }),
                    onSelectAll: () => setState(() {
                      _selectedPaths.addAll(
                        _visibleFiles.map((file) => file.path),
                      );
                      _selectedFile = _visibleFiles.lastOrNull;
                    }),
                    showHidden: _showHidden,
                    onToggleHiddenView: () => setState(() {
                      _showHidden = !_showHidden;
                      _selectedFile = null;
                      _selectedPaths.clear();
                      _selectionAnchor = null;
                    }),
                    onToggleHidden: _selectedPaths.isEmpty || _savingHidden
                        ? null
                        : () => _setHidden(
                            _imageFiles
                                .where(
                                  (file) => _selectedPaths.contains(file.path),
                                )
                                .toList(),
                            hide: !_showHidden,
                          ),
                    selectedFile: _selectedFile,
                    status: _status,
                    isRunning: _isRunning,
                    onRefresh: _refreshLibrary,
                    onOpenSelected: _selectedPaths.length != 1
                        ? null
                        : () => _openFile(_selectedFile!),
                    onOpenSelectedFolder: _selectedPaths.length != 1
                        ? null
                        : () => _openFolder(_selectedFile!.parent.path),
                    onSetWallpaper: _selectedPaths.length != 1
                        ? null
                        : () => _setWallpaper(_selectedFile!),
                  ),
                  Expanded(child: _buildGallery()),
                  if (_logs.isNotEmpty || _lastPayload != null)
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
    if (_hiddenLoadFailed) {
      return const Center(child: Text('隐藏记录读取失败，请刷新重试。'));
    }
    final files = _visibleFiles;
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
      child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : files.isEmpty && _showHidden
          ? const Center(child: Text('暂无已隐藏的壁纸'))
          : files.isEmpty
          ? const _EmptyGallery()
          : GridView.builder(
              key: ValueKey(
                _showHidden ? 'hidden-gallery-grid' : 'gallery-grid',
              ),
              controller: _showHidden
                  ? _hiddenGalleryController
                  : _galleryController,
              padding: const EdgeInsets.all(24),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: _gridItemWidth,
                childAspectRatio: 1.45,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              itemCount: files.length,
              findChildIndexCallback: (key) {
                final index = files.indexWhere(
                  (file) => ValueKey(file.path) == key,
                );
                return index < 0 ? null : index;
              },
              itemBuilder: (context, index) {
                final file = files[index];
                return _WallpaperTile(
                  key: ValueKey(file.path),
                  file: file,
                  selected: _selectedPaths.contains(file.path),
                  onSelected: () => _selectFile(file),
                  onOpenPreview: () => _openPreview(file),
                );
              },
            ),
    );
  }

  Future<void> _refreshLibrary() async {
    _loadHidden();
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
        _selectedPaths.retainAll(_visibleFiles.map((file) => file.path));
        _selectedFile = files
            .where((file) => _selectedPaths.contains(file.path))
            .lastOrNull;
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
    await _runWallhavenJob('更新', ['quick-update']);
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

    if (widget.refreshAfterJob) {
      await _refreshLibrary();
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

  void _selectFile(File file) {
    final keyboard = HardwareKeyboard.instance;
    final additive =
        _multiSelect || keyboard.isControlPressed || keyboard.isMetaPressed;
    final files = _visibleFiles;
    final anchorIndex = files.indexWhere(
      (item) => item.path == _selectionAnchor,
    );
    final targetIndex = files.indexWhere((item) => item.path == file.path);
    setState(() {
      if (keyboard.isShiftPressed && anchorIndex >= 0 && targetIndex >= 0) {
        if (!additive) _selectedPaths.clear();
        final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
        final end = anchorIndex > targetIndex ? anchorIndex : targetIndex;
        _selectedPaths.addAll(
          files.sublist(start, end + 1).map((item) => item.path),
        );
      } else {
        if (additive && _selectedPaths.contains(file.path)) {
          _selectedPaths.remove(file.path);
        } else {
          if (!additive) _selectedPaths.clear();
          _selectedPaths.add(file.path);
        }
        _selectionAnchor = file.path;
      }
      _selectedFile = _selectedPaths.contains(file.path)
          ? file
          : _imageFiles
                .where((item) => _selectedPaths.contains(item.path))
                .lastOrNull;
    });
  }

  void _openPreview(File file) {
    if (!_selectedPaths.contains(file.path)) _selectFile(file);
    _preview.value = file;
  }

  void _closePreview() => _preview.value = null;

  void _loadHidden() {
    try {
      _hidden
        ..clear()
        ..addAll(_hiddenStore.load());
      _hiddenLoadFailed = false;
    } catch (error) {
      _hiddenLoadFailed = true;
      _logs.add('隐藏记录读取失败: $error');
    }
  }

  Future<void> _toggleHidden(File file) async {
    await _setHidden([
      file,
    ], hide: !_hidden.contains(_hiddenStore.keyFor(file)));
  }

  Future<void> _setHidden(List<File> files, {required bool hide}) async {
    if (_savingHidden || _hiddenLoadFailed) return;
    if (files.isEmpty) return;
    setState(() => _savingHidden = true);
    final next = {..._hidden};
    final keys = files.map(_hiddenStore.keyFor);
    if (hide) {
      next.addAll(keys);
    } else {
      next.removeAll(keys);
    }
    try {
      await _hiddenStore.save(next);
      if (!mounted) return;
      _closePreview();
      setState(() {
        _hidden
          ..clear()
          ..addAll(next);
        _selectedFile = null;
        _selectedPaths.clear();
        _selectionAnchor = null;
      });
      _showSnack(
        hide ? '已隐藏 ${files.length} 张，可在「查看已隐藏」中恢复' : '已恢复显示 ${files.length} 张',
      );
    } catch (error) {
      _showSnack('保存隐藏记录失败');
      _appendLog('保存隐藏记录失败: $error');
    } finally {
      if (mounted) setState(() => _savingHidden = false);
    }
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
  const _ControlRail({required this.isRunning, required this.onUpdate});

  final bool isRunning;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 208,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.landscape_outlined, color: _accent, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'Da Downloader',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: _text,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Wallhaven 壁纸收藏',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 40),
          _PrimaryButton(
            icon: Icons.sync_rounded,
            label: isRunning ? '正在更新…' : '一键更新',
            onPressed: isRunning ? null : onUpdate,
          ),
          const SizedBox(height: 14),
          const Text(
            '收藏里的新风景，一键保存到本地。',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.8),
          ),
          const Spacer(),
          const Text(
            '让桌面，换一片风景。',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
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
    required this.showHidden,
    required this.onToggleHiddenView,
    required this.onToggleHidden,
    required this.selectionCount,
    required this.multiSelect,
    required this.onToggleMultiSelect,
    required this.onSelectAll,
  });

  final int count;
  final File? selectedFile;
  final String status;
  final bool isRunning;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenSelected;
  final VoidCallback? onOpenSelectedFolder;
  final VoidCallback? onSetWallpaper;
  final bool showHidden;
  final VoidCallback onToggleHiddenView;
  final VoidCallback? onToggleHidden;
  final int selectionCount;
  final bool multiSelect;
  final VoidCallback onToggleMultiSelect;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final selectedName = multiSelect || selectionCount > 1
        ? '已选择 $selectionCount 张'
        : selectedFile == null
        ? (showHidden ? '已隐藏的壁纸' : '我的壁纸')
        : selectedFile!.uri.pathSegments.last;

    return Container(
      height: 92,
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
                  multiSelect
                      ? '$count 张 · 点击选择或取消，Shift 连选'
                      : '$count 张 · $status',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            icon: multiSelect ? Icons.close_rounded : Icons.checklist_rounded,
            tooltip: multiSelect ? '退出多选' : '多选壁纸',
            onPressed: onToggleMultiSelect,
          ),
          if (multiSelect)
            _HeaderIcon(
              icon: Icons.select_all_rounded,
              tooltip: '全选',
              onPressed: onSelectAll,
            ),
          _HeaderIcon(
            icon: showHidden
                ? Icons.photo_library_outlined
                : Icons.visibility_off_outlined,
            tooltip: showHidden ? '返回图库' : '查看已隐藏',
            onPressed: onToggleHiddenView,
          ),
          _HeaderIcon(
            icon: showHidden
                ? Icons.visibility_outlined
                : Icons.hide_image_outlined,
            tooltip: showHidden ? '恢复显示' : '隐藏所选壁纸',
            onPressed: onToggleHidden,
          ),
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
    super.key,
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
  Offset? _pressPosition;
  int? _pressPointer;
  bool _secondTap = false;

  @override
  Widget build(BuildContext context) {
    final showOverlay = _hovered || widget.selected;
    final filename = widget.file.uri.pathSegments.last;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        // Selection must not wait for the double-tap recognizer's timeout.
        // Track movement so dragging the gallery never changes selection.
        onPointerDown: (event) {
          if (event.buttons != kPrimaryMouseButton) return;
          _pressPosition = event.position;
          _pressPointer = event.pointer;
          _secondTap = false;
        },
        onPointerMove: (event) {
          if (event.pointer == _pressPointer &&
              _pressPosition != null &&
              (event.position - _pressPosition!).distance > kTouchSlop) {
            _pressPosition = null;
          }
        },
        onPointerCancel: (_) => _pressPosition = null,
        onPointerUp: (event) {
          if (event.pointer == _pressPointer &&
              _pressPosition != null &&
              !_secondTap) {
            widget.onSelected();
          }
          _pressPosition = null;
        },
        child: GestureDetector(
          onDoubleTapDown: (_) => _secondTap = true,
          onDoubleTap: widget.onOpenPreview,
          child: Container(
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
                  Image.file(
                    widget.file,
                    // Keep thumbnail decode/cache independent from the preview.
                    cacheWidth: 512,
                    gaplessPlayback: true,
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
                  AnimatedOpacity(
                    opacity: showOverlay ? 1 : 0,
                    duration: const Duration(milliseconds: 80),
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
                  if (widget.selected)
                    const Positioned(
                      right: 10,
                      top: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _ink,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: _accent,
                          size: 22,
                        ),
                      ),
                    ),
                ],
              ),
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
      height: 140,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 260,
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
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: _surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.landscape_outlined,
                color: _accent,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '等待第一片风景',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: _text,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '点击左侧「一键更新」，收藏的壁纸就会出现在这里。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13, height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}

class WallpaperPreviewPage extends StatelessWidget {
  const WallpaperPreviewPage({
    super.key,
    required this.imageFile,
    required this.onClose,
    required this.onToggleHidden,
    required this.isHidden,
  });

  final File imageFile;
  final VoidCallback onClose;
  final VoidCallback onToggleHidden;
  final bool isHidden;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            imageFile,
            fit: BoxFit.contain,
            cacheWidth:
                (MediaQuery.sizeOf(context).width *
                        MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
            errorBuilder: (context, error, stack) =>
                const Center(child: Text('图片无法读取')),
          ),
          Positioned(
            top: 18,
            left: 18,
            child: _PreviewToolbar(
              children: [
                _PreviewIcon(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回',
                  onPressed: onClose,
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
                  icon: isHidden
                      ? Icons.visibility_outlined
                      : Icons.hide_image_outlined,
                  tooltip: isHidden ? '恢复显示' : '隐藏这张壁纸',
                  onPressed: onToggleHidden,
                ),
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
