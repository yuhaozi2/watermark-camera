import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// 本地相册：拍照页、拼图页生成的水印照片都会同步存一份到应用目录 wm_photos，
// 这里按修改时间倒序列出来，可以查看、分享、删除。视频不进相册（只分享成片）。
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<File> photos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/wm_photos');
      if (!await dir.exists()) {
        if (mounted) setState(() => photos = []);
        return;
      }
      final files = <File>[];
      await for (final e in dir.list()) {
        if (e is File) {
          final lower = e.path.toLowerCase();
          if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) files.add(e);
        }
      }
      files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      if (mounted) setState(() => photos = files);
    } catch (_) {}
  }

  Future<void> _open(File file) async {
    final confirmedDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Image.file(file, fit: BoxFit.contain),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('关闭')),
          TextButton(
            onPressed: () async {
              await Share.shareXFiles([XFile(file.path)], text: '水印照片');
              if (ctx.mounted) Navigator.pop(ctx, false);
            },
            child: const Text('分享'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmedDelete == true) {
      try {
        await file.delete();
      } catch (_) {}
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的照片'), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: photos.isEmpty
          ? const Center(child: Text('还没有照片\n生成一张水印照片或拼图就会自动存到这里', textAlign: TextAlign.center))
          : GridView.count(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              padding: const EdgeInsets.all(8),
              children: [
                for (final f in photos)
                  GestureDetector(
                    onTap: () => _open(f),
                    child: Image.file(f, fit: BoxFit.cover),
                  ),
              ],
            ),
    );
  }
}
