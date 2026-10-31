import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'puzzle_page.dart';

const templates = [
  '时间地点', '打卡考勤', '工作记录', '会议', '监理巡检',
  '工程项目', '物业', '销售', '电力', '团队品牌',
  '简洁水印', '对比拼图', '工作汇报拼图', '日常拼图',
];

// 1:1 比对用的原包预设拼图字段 / 主题色 / 默认标题
// 来源：preset_puzzle/*.zip 的 string.json + color.json + layout.xml，只取字段名、顺序、颜色、字号比例，不复制原厂图片
// layout.xml 规律：标题居中、字号 42、主题色、加粗；正文字号 22、内容色 #232325；6 列网格，colSpan 3 = 半行，6 = 整行
class TemplateSpec {
  final int themeColor;
  final String defaultTitle;
  final String defaultContent;
  final List<String> fields;
  final List<List<String>> headerRows;
  const TemplateSpec(this.themeColor, this.defaultTitle, this.defaultContent, this.fields, this.headerRows);
}

const puzzleSpecs = {
  '对比拼图': TemplateSpec(0xFF5076FF, '物业清洁', '现场清洁照片记录',
      ['汇报人', '天气', '工作前', '工作后', '检查总结', '问题描述', '问题详情'],
      [['汇报人'], ['日期'], ['天气'], ['工作前', '工作后']]),
  '会议': TemplateSpec(0xFFFF371C, '会议纪要', '',
      ['主持人', '记录人', '参与人', '会议地点', '会议主题', '会议内容', '天气'],
      [['主持人', '日期'], ['记录人'], ['参与人'], ['会议地点']]),
  '监理巡检': TemplateSpec(0xFF2E5BFF, '监理日志', '',
      ['汇报人', '上午天气', '下午天气', '记录人', '审核人', '施工情况记录', '今日现场情况', '今日施工质量方面', '今日协调事项及重要事项'],
      [['日期'], ['上午天气', '下午天气'], ['记录人', '审核人']]),
  '工作汇报拼图': TemplateSpec(0xFF2E5BFF, '工作汇报', '工作现场照片汇总整理',
      ['汇报人', '天气', '检查总结', '问题描述', '问题详情'],
      [['汇报人', '日期'], ['天气']]),
  '日常拼图': TemplateSpec(0xFF2D38B9, '物业周报', '本周工作汇报',
      ['汇报人', '天气', '保洁绿化服务', '工程维修服务', '物业品质检查', '客服接待服务', '日常工作规划'],
      [['汇报人', '日期'], ['天气']]),
};

// 单张水印模板的功能字段（非原包提取，原包水印包只有图片、无模板 JSON，故按行业通用字段定义，不复制原图）
const singleSpecs = {
  '时间地点': TemplateSpec(0xFF2E5BFF, '时间地点', '', ['地点', '经纬度'], []),
  '打卡考勤': TemplateSpec(0xFF2E5BFF, '打卡考勤', '', ['姓名', '考勤类型', '地点'], []),
  '工作记录': TemplateSpec(0xFF2E5BFF, '工作记录', '', ['项目', '工单', '工作内容', '备注'], []),
  '工程项目': TemplateSpec(0xFF2E5BFF, '工程项目', '', ['项目名称', '施工单位', '监理单位', '备注'], []),
  '物业': TemplateSpec(0xFF5076FF, '物业', '', ['小区', '区域', '汇报人'], []),
  '销售': TemplateSpec(0xFFFF371C, '销售', '', ['门店', '销售员', '客户', '备注'], []),
  '电力': TemplateSpec(0xFF2E5BFF, '电力', '', ['变电站', '设备', '操作人'], []),
  '团队品牌': TemplateSpec(0xFF2E5BFF, '团队品牌', '', ['品牌名称', '团队', '地点'], []),
};

TemplateSpec? specFor(String t) => puzzleSpecs[t] ?? singleSpecs[t];

String formatNow() {
  final d = DateTime.now();
  const week = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)} ${week[d.weekday % 7]}';
}

class WatermarkCameraPage extends StatefulWidget {
  const WatermarkCameraPage({super.key});
  @override
  State<WatermarkCameraPage> createState() => _WatermarkCameraPageState();
}

class _WatermarkCameraPageState extends State<WatermarkCameraPage> {
  final picker = ImagePicker();
  final boundaryKey = GlobalKey();
  File? image;
  String template = '时间地点';
  String customText = '';
  String locationText = '';
  String remark = '';
  String projectText = '';
  String position = '左下';
  String timeText = '';
  final Map<String, String> fieldValues = {};
  Color watermarkColor = Colors.white;
  double watermarkSize = 13;
  double watermarkOpacity = 0.55;
  String ratio = '4:3';
  bool showGrid = false;

  @override
  void initState() {
    super.initState();
    timeText = formatNow();
  }

  Future<void> pick(ImageSource source) async {
    final x = await picker.pickImage(source: source);
    if (x != null) setState(() { image = File(x.path); timeText = formatNow(); });
  }

  Future<void> locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('定位权限被拒，请手填地点')));
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() => locationText = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
  }

  List<String> lines() {
    if (template == '简洁水印') return [timeText];
    final spec = specFor(template);
    final title = spec?.defaultTitle ?? template;
    final l = <String>[title, timeText];
    if (spec != null) {
      if (spec.defaultContent.isNotEmpty) l.add(spec.defaultContent);
      for (final f in spec.fields) {
        final v = fieldValues[f];
        if (v != null && v.isNotEmpty) l.add('$f：$v');
      }
    }
    if (projectText.isNotEmpty) l.add('项目：$projectText');
    if (locationText.isNotEmpty) l.add(locationText);
    if (customText.isNotEmpty) l.add(customText);
    if (remark.isNotEmpty) l.add(remark);
    return l;
  }

  Future<void> save() async {
    try {
      final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/watermark_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '水印照片');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已生成，可在分享面板里保存到相册')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBottom = position.contains('下');
    final isRight = position.contains('右');
    final spec = specFor(template);
    final isPuzzle = puzzleSpecs.containsKey(template);
    final themeColor = spec != null ? Color(spec.themeColor) : Colors.blue;
    final previewHeight = ratio == '16:9' ? 220.0 : ratio == '1:1' ? 360.0 : ratio == '3:4' ? 420.0 : 360.0;
    return Scaffold(
      appBar: AppBar(title: Text('水印相机 · ${spec?.defaultTitle ?? template}'), backgroundColor: themeColor, foregroundColor: Colors.white,
        actions: [
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PuzzlePage())), child: const Text('拼图模式', style: TextStyle(color: Colors.white))),
        ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RepaintBoundary(
            key: boundaryKey,
            child: Container(
              height: previewHeight,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
              child: Stack(children: [
                if (image != null)
                  Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(image!, fit: BoxFit.cover)))
                else
                  const Center(child: Text('还没有照片\n点下面拍照或导入', textAlign: TextAlign.center)),
                if (image != null)
                  Positioned(
                    left: isRight ? null : 12, right: isRight ? 12 : null,
                    top: isBottom ? null : 12, bottom: isBottom ? 12 : null,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(watermarkOpacity), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                        for (final line in lines())
                          Text(line, style: TextStyle(color: watermarkColor, fontSize: watermarkSize, height: 1.5)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
          if (isPuzzle && spec != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                      Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('$f：${f == '日期' ? timeText.split(' ').first : (fieldValues[f] ?? '')}', style: const TextStyle(fontSize: 15, color: Color(0xFF232325))))),
                  ]),
                const SizedBox(height: 4),
                const Text('拼图头预览（按原 layout.xml 的行 / 列顺序，不含原厂图片）', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          const Text('模板分类'),
          Wrap(spacing: 8, children: [
            for (final t in templates)
              ChoiceChip(label: Text(t), selected: template == t, onSelected: (_) => setState(() => template = t)),
          ]),
          if (spec != null) ...[
            const SizedBox(height: 8),
            Text('按原模板字段填写（${spec.defaultTitle}）', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
            for (final f in spec.fields)
              TextField(decoration: InputDecoration(labelText: f), onChanged: (v) => setState(() => fieldValues[f] = v)),
          ],
          TextField(decoration: const InputDecoration(labelText: '项目 / 工单'), onChanged: (v) => projectText = v),
          TextField(decoration: const InputDecoration(labelText: '水印文字'), onChanged: (v) => customText = v),
          Row(children: [
            Expanded(child: TextField(decoration: const InputDecoration(labelText: '地点'), controller: TextEditingController(text: locationText), onChanged: (v) => locationText = v)),
            TextButton(onPressed: locate, child: const Text('定位')),
          ]),
          TextField(decoration: const InputDecoration(labelText: '备注（天气、人员等）'), onChanged: (v) => remark = v),
          const SizedBox(height: 8),
          const Text('水印位置'),
          Wrap(spacing: 8, children: [
            for (final p in ['左下', '右下', '左上', '右上'])
              ChoiceChip(label: Text(p), selected: position == p, onSelected: (_) => setState(() => position = p)),
          ]),
          const SizedBox(height: 8),
          const Text('水印颜色'),
          Wrap(spacing: 8, children: [
            for (final c in [Colors.white, Colors.yellow, Colors.blue, Colors.red, Colors.black])
              GestureDetector(onTap: () => setState(() => watermarkColor = c), child: Container(width: 28, height: 28, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: watermarkColor == c ? Colors.blue : Colors.grey)))),
          ]),
          Row(children: [const Text('字号'), Expanded(child: Slider(value: watermarkSize, min: 10, max: 20, onChanged: (v) => setState(() => watermarkSize = v)))]),
          Row(children: [const Text('透明度'), Expanded(child: Slider(value: watermarkOpacity, min: 0.3, max: 0.9, onChanged: (v) => setState(() => watermarkOpacity = v)))]),
          const Text('画幅'),
          Wrap(spacing: 8, children: [
            for (final r in ['4:3', '16:9', '1:1', '3:4'])
              ChoiceChip(label: Text(r), selected: ratio == r, onSelected: (_) => setState(() => ratio = r)),
          ]),
          Row(children: [const Text('网格线'), Switch(value: showGrid, onChanged: (v) => setState(() => showGrid = v)), const Text('（预览辅助，不影响原图）')]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: () => pick(ImageSource.camera), child: const Text('拍照'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: () => pick(ImageSource.gallery), child: const Text('导入照片'))),
          ]),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: image == null ? null : save, child: const Text('生成并分享 / 保存')),
          const SizedBox(height: 12),
          const Text('说明：本项目为干净重写版，不含原厂图片、账号、VIP、团队同步和云端功能。拼图、视频水印按模板思路实现，见 README。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
