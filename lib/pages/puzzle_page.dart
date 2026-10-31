import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'watermark_camera_page.dart';

// 多图拼图页：干净重写版
// 结构按原包 preset_puzzle 的头 + 条目 + 照片区：头（品牌占位 + 标题 + 字段行）+ 每张照片 + 说明
// 不使用原厂图片、装饰图、logo
class PuzzlePage extends StatefulWidget {
  const PuzzlePage({super.key});
  @override
  State<PuzzlePage> createState() => _PuzzlePageState();
}

class _PuzzlePageState extends State<PuzzlePage> {
  final picker = ImagePicker();
  final boundaryKey = GlobalKey();
  String template = '会议';
  final List<XFile> photos = [];
  final Map<String, String> fieldValues = {};

  Future<void> pickMulti() async {
    final list = await picker.pickMultiImage();
    if (list.isNotEmpty) setState(() => photos.addAll(list));
  }

  Future<void> save() async {
    try {
      final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/puzzle_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '拼图照片');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('拼图已生成，可在分享面板里保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = puzzleSpecs[template];
    final themeColor = spec != null ? Color(spec.themeColor) : Colors.blue;
    return Scaffold(
      appBar: AppBar(title: Text('拼图 · ${spec?.defaultTitle ?? template}'), backgroundColor: themeColor, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, children: [
            for (final t in puzzleSpecs.keys)
              ChoiceChip(label: Text(t), selected: template == t, onSelected: (_) => setState(() => template = t)),
          ]),
          const SizedBox(height: 12),
          if (spec != null) ...[
            for (final f in spec.fields)
              TextField(decoration: InputDecoration(labelText: f), onChanged: (v) => setState(() => fieldValues[f] = v)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: pickMulti, child: Text('添加照片（已选 ${photos.length} 张）'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: photos.isEmpty ? null : save, child: const Text('生成拼图并分享'))),
          ]),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: boundaryKey,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
                  const SizedBox(width: 8),
                  Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
                ]),
                const SizedBox(height: 8),
                Text(spec?.defaultTitle ?? template, textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 28, fontWeight: FontWeight.bold)),
                if (spec != null && spec.defaultContent.isNotEmpty) Text(spec.defaultContent, textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 15)),
                const SizedBox(height: 8),
                if (spec != null)
                  for (final row in spec.headerRows)
                    Row(children: [
                      for (final f in row)
                        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('$f：${fieldValues[f] ?? ''}', style: const TextStyle(fontSize: 15, color: Color(0xFF232325))))),
                    ]),
                const SizedBox(height: 12),
                if (photos.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('还没有照片，点上面添加照片'))),
                for (final p in photos) ...[
                  Image.file(File(p.path), height: 220, fit: BoxFit.cover),
                  const SizedBox(height: 8),
                ],
                if (spec != null)
                  for (final f in spec.fields)
                    if ((fieldValues[f] ?? '').isNotEmpty)
                      Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(8)), child: Text('$f：${fieldValues[f]}', style: const TextStyle(fontSize: 14))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text('说明：多图拼图为干净重写版，头 + 字段 + 照片纵排，不含原厂图片、装饰、VIP、云端。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
