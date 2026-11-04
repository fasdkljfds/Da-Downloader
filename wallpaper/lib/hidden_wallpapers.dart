import 'dart:convert';
import 'dart:io';

/// Stores paths relative to the library, so moving the library keeps choices.
class HiddenWallpapers {
  HiddenWallpapers(String directory)
    : root = Directory(directory).absolute,
      file = File('$directory${Platform.pathSeparator}.hidden-wallpapers.json');

  final Directory root;
  final File file;

  String keyFor(File image) =>
      image.absolute.uri.toString().substring(root.uri.toString().length);

  Set<String> load() {
    if (!file.existsSync()) return {};
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! List || decoded.any((entry) => entry is! String)) {
      throw const FormatException('隐藏记录格式不正确');
    }
    return decoded.cast<String>().toSet();
  }

  Future<void> save(Set<String> paths) async {
    await root.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(paths.toList()..sort()),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}
