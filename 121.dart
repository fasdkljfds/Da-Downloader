import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const ElegantWallpaperApp());
}

class ElegantWallpaperApp extends StatelessWidget {
  const ElegantWallpaperApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小美壁纸',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212), // 极简的高级暗黑背景
        colorScheme: ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.grey.shade800,
        ),
      ),
      home: const WallpaperHomePage(),
    );
  }
}

class WallpaperHomePage extends StatefulWidget {
  const WallpaperHomePage({super.key});

  @override
  State<WallpaperHomePage> createState() => _WallpaperHomePageState();
}

class _WallpaperHomePageState extends State<WallpaperHomePage> {
  List<File> _imageFiles =[];
  bool _isLoading = false;

  // 核心功能1：打开文件夹并读取图片
  Future<void> _pickFolderAndLoadImages() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory == null) return; // 用户取消了选择

    setState(() {
      _isLoading = true;
    });

    try {
      final directory = Directory(selectedDirectory);
      final List<FileSystemEntity> entities = await directory.list().toList();
      
      // 过滤出 jpg 和 png 文件
      final List<File> images = entities.whereType<File>().where((file) {
        final path = file.path.toLowerCase();
        return path.endsWith('.jpg') || path.endsWith('.jpeg') || path.endsWith('.png');
      }).toList();

      setState(() {
        _imageFiles = images;
      });
    } catch (e) {
      debugPrint("读取文件夹失败: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Gallery",
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions:[
          if (_imageFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.folder_open_rounded),
              tooltip: "重新选择文件夹",
              onPressed: _pickFolderAndLoadImages,
            )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _imageFiles.isEmpty
              ? _buildEmptyState()
              : _buildImageGrid(),
    );
  }

  // 核心功能2：初始空白页与大文件夹符号
  Widget _buildEmptyState() {
    return Center(
      child: GestureDetector(
        onTap: _pickFolderAndLoadImages,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade900,
                boxShadow:[
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              // 现代感十足的发光文件夹图标
              child: const Icon(
                Icons.create_new_folder_rounded,
                size: 80,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "点击选择壁纸文件夹",
              style: TextStyle(
                fontSize: 16,
                color: Colors.white54,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w500,
              ),
            )
          ],
        ),
      ),
    );
  }

  // 核心功能3：缩略图展示
  Widget _buildImageGrid() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 两列布局
        childAspectRatio: 0.65, // 偏长方形，适合手机壁纸比例
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _imageFiles.length,
      itemBuilder: (context, index) {
        final file = _imageFiles[index];
        return GestureDetector(
          onTap: () {
            // 点击弹出大图AA
            Navigator.push(
              context,
              PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 400),
                pageBuilder: (_, __, ___) => ImagePreviewPage(imageFile: file),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              ),
            );
          },
          child: Hero(
            tag: file.path, // 开启Hero动画，图片飞跃效果
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                // 加载过程中的过渡效果
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    child: child,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// 核心功能4 & 5：大图预览与确认更换按钮
class ImagePreviewPage extends StatelessWidget {
  final File imageFile;

  const ImagePreviewPage({super.key, required this.imageFile});

  // 模拟更换壁纸的方法
  void _setWallpaper(BuildContext context) {
    // 【TODO】在此处调用具体平台的壁纸设置API
    // 比如使用 async_wallpaper 插件:
    // await AsyncWallpaper.setWallpaperFromFile(file.path, AsyncWallpaper.HOME_SCREEN);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("壁纸更换成功！", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children:[
          // 1. 全屏大图 (利用 Hero 实现丝滑过渡)
          Hero(
            tag: imageFile.path,
            child: Image.file(
              imageFile,
              fit: BoxFit.cover,
            ),
          ),
          
          // 2. 顶部返回按钮 (带毛玻璃背景)
          Positioned(
            top: 50,
            left: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withOpacity(0.2),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),

          // 3. 底部“确认更换”按钮 (高级毛玻璃悬浮效果)
          Positioned(
            bottom: 40,
            left: 40,
            right: 40,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: GestureDetector(
                  onTap: () => _setWallpaper(context),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:[
                        Icon(Icons.wallpaper_rounded, color: Colors.white),
                        SizedBox(width: 12),
                        Text(
                          "确认更换",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
