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
// 工作汇报拼图（work-report，id 1001）按 layout.xml 精确排：
//   品牌 110x34 + Logo 34x34（上边距 12）→ 标题居中 28 号主题色加粗 → 内容居中 15 号主题色
//   → 1px 分隔线 #E9ECF3 → 同一行：左 汇报人（标签加粗），右 日期（yyyy年MM月dd日）+ 天气，字色 #50607A、14 号
//   → 自定义条目（检查总结 / 问题描述 / 问题详情）：标题加粗 14 号 #50607A，内容 14 号 #50607A，背景 #F6F7FB，顶部 1px 分隔线
//   → 头下装饰线：2 白 / 2 主题色 / 2 白 / 4 主题色 → 照片区（间距 8）
class PuzzlePage extends StatefulWidget {
  const PuzzlePage({super.key});
  @override
  State<PuzzlePage> createState() => _PuzzlePageState();
}

String _todayCn() {
  final d = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}年${p(d.month)}月${p(d.day)}日';
}

class _PuzzlePageState extends State<PuzzlePage> {
  final picker = ImagePicker();
  final boundaryKey = GlobalKey();
  String template = '工作汇报拼图';
  final List<XFile> photos = [];
  final Map<String, String> fieldValues = {};

  @override
  void initState() {
    super.initState();
    fieldValues['日期'] = _todayCn();
  }

  bool get isWorkReport => template == '工作汇报拼图';
  List<String> get inputFields {
    if (isWorkReport) return const ['汇报人', '日期', '天气', '检查总结', '问题描述', '问题详情'];
    return puzzleSpecs[template]?.fields ?? [];
  }

  List<String> get workItems => const ['检查总结', '问题描述', '问题详情'];

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

  Widget _workReportHeader(Color themeColor) {
    const itemColor = Color(0xFF50607A);
    const dividerColor = Color(0xFFE9ECF3);
    final reporter = fieldValues['汇报人'] ?? '';
    final date = fieldValues['日期'] ?? _todayCn();
    final weather = fieldValues['天气'] ?? '';
    final right = weather.isEmpty ? date : '$date $weather';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
      ]),
      const SizedBox(height: 5),
      const Text('工作汇报', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF2E5BFF), fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      const Text('工作现场照片汇总整理', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF2E5BFF), fontSize: 15)),
      const SizedBox(height: 8),
      Container(height: 1, color: dividerColor),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: itemColor), children: [const TextSpan(text: '汇报人：', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: reporter)]))),
        Expanded(child: Text(right, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, color: itemColor))),
      ]),
      const SizedBox(height: 8),
      for (final f in workItems)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: const BoxDecoration(color: Color(0xFFF6F7FB)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 1, color: dividerColor),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f, style: const TextStyle(fontSize: 14, color: itemColor, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text((fieldValues[f] ?? '').isEmpty ? '点击输入内容' : fieldValues[f]!, style: TextStyle(fontSize: 14, color: (fieldValues[f] ?? '').isEmpty ? Colors.grey : itemColor)),
              ]),
            ),
          ]),
        ),
      // 头下装饰线：2 白 / 2 主题色 / 2 白 / 4 主题色，左右各留 8
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(children: [
        Container(height: 2, color: Colors.white),
        Container(height: 2, color: themeColor),
        Container(height: 2, color: Colors.white),
        Container(height: 4, color: themeColor),
      ])),
      const SizedBox(height: 8),
    ]);
  }

  Widget _genericHeader(TemplateSpec spec, Color themeColor) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
      ]),
      const SizedBox(height: 8),
      Text(spec.defaultTitle, textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 28, fontWeight: FontWeight.bold)),
      if (spec.defaultContent.isNotEmpty) Text(spec.defaultContent, textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 15)),
      const SizedBox(height: 8),
      for (final row in spec.headerRows)
        Row(children: [
          for (final f in row)
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('$f：${fieldValues[f] ?? ''}', style: const TextStyle(fontSize: 15, color: Color(0xFF232325))))),
        ]),
      const SizedBox(height: 12),
    ]);
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
          for (final f in inputFields)
            TextFormField(
              decoration: InputDecoration(labelText: f, hintText: workItems.contains(f) ? '点击输入内容' : null),
              initialValue: f == '日期' ? fieldValues['日期'] : null,
              onChanged: (v) => setState(() => fieldValues[f] = v),
            ),
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
                if (isWorkReport) _workReportHeader(themeColor) else if (spec != null) _genericHeader(spec, themeColor),
                if (photos.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('还没有照片，点上面添加照片'))),
                for (final p in photos) ...[
                  Image.file(File(p.path), height: 220, fit: BoxFit.cover),
                  const SizedBox(height: 8),
                ],
                if (!isWorkReport && spec != null)
                  for (final f in spec.fields)
                    if ((fieldValues[f] ?? '').isNotEmpty)
                      Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(8)), child: Text('$f：${fieldValues[f]}', style: const TextStyle(fontSize: 14))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text('说明：多图拼图为干净重写版，头 + 字段 + 照片纵排，不含原厂图片、装饰、VIP、云端。工作汇报拼图已按原 layout.xml 的头顺序、颜色、字号排版。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
