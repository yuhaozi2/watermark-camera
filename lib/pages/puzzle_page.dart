import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'watermark_camera_page.dart';
import '../docx_export.dart';

// 多图拼图页：干净重写版
// 结构按原包 preset_puzzle 的头 + 条目 + 照片区：头（品牌占位 + 标题 + 字段行）+ 每张照片 + 说明
// 不使用原厂图片、装饰图、logo
// 工作汇报拼图（work-report，id 1001）按 layout.xml 精确排：
//   品牌 110x34 + Logo 34x34（上边距 12）→ 标题居中 28 号主题色加粗 → 内容居中 15 号主题色
//   → 1px 分隔线 #E9ECF3 → 同一行：左 汇报人（标签加粗），右 日期（yyyy年MM月dd日）+ 天气，字色 #50607A、14 号
//   → 自定义条目（检查总结 / 问题描述 / 问题详情）：标题加粗 14 号 #50607A，内容 14 号 #50607A，背景 #F6F7FB，顶部 1px 分隔线
//   → 头下装饰线：2 白 / 2 主题色 / 2 白 / 4 主题色 → 照片区（间距 8）
// 会议纪要（meeting，id 1008）按 layout.xml 精确排：
//   品牌 110x34 + Logo 34x34 → 标题居中 32 号主题色 #FF371C 加粗（原包无默认内容，不出内容行）
//   → 同一行：左 主持人，右 日期 yyyy年MM月dd日，字色 #232325、14 号 → 2px 主题色线
//   → 带边框的表（左右 + 顶部 1px 线，线色 #232325）：记录人 / 参与人 / 会议地点 / 会议主题 / 会议内容，
//     每行 8 边距、行间 1px 线，标题色 #A8A8A8、内容色 #232325、14 号，标题后 3 个空格分隔
//   → 照片区（间距 8）。注意：原 layout.xml 头里没有天气行，天气只在 string.json 字段里，不进头预览。
// 监理日志（supervision，id 1007）按 layout.xml 精确排：
//   品牌 110x34 + Logo 34x34 → 标题居中 32 号主题色 #2E5BFF 加粗（原包无默认内容，不出内容行）
//   → 带边框的表（左右 + 顶部 1px 主题色线）：日期（整行，dateFormat 为 yyyy.MM.dd）→ 上午天气 | 下午天气（中间 1px 竖线）
//     → 记录人 | 审核人（中间 1px 竖线）→ 4 条自定义条目：施工情况记录 / 今日现场情况 / 今日施工质量方面 / 今日协调事项及重要事项，
//     每行 8 边距、行间 1px 主题色线，标题色主题色、内容色 #232325、14 号
//   → 表下 10 白 → 装饰线 2 主题色 / 2 白 / 4 主题色 → 照片区（间距 8）。原 string.json 里的汇报人、天气不在头里，不进预览。
// 对比拼图（compare，id 1009）按 layout.xml 精确排：
//   品牌 110x34 + Logo 34x34 → 标题 40 号主题色 #5076FF 居中 → 内容主题色 14 号居中“现场清洁照片记录”
//   → 汇报人 / 日期（yyyy年MM月dd日）/ 天气，各整行，标题主题色、内容 #232325、14 号
//   → 自定义条目（检查总结 / 问题描述 / 问题详情）：标题主题色、内容 #232325、背景 #F6F7FB、顶部 1px 主题色线、空值“点击输入内容”
//   → 30 高主题色条：左“工作前”、右“工作后”，白字 15 号居中，中间 1px 白竖线 → 照片区：前两张左右并排（前/后），其余纵排
// 日常拼图 / 物业周报（vip_daily，id 25，puzzleType=template，max_photo_count=19）按 layout.xml 精确排：
//   白色头卡：品牌 110x34 + Logo 34x34 + 日期右对齐主题色 → 2px 主题色线
//   → 左：标题 32 号主题色加粗 + 红色条（#E73558）白字 14 号“本周工作汇报”；右：1px 红边框白底盒，汇报人（默认张三）/ 天气，标题加粗红色、内容红色，中间 1px 红线
//   → 5 个分区卡（白底、圆角 4、0.5 边）：保洁绿化服务 / 工程维修服务 / 物业品质检查 / 客服接待服务 / 日常工作规划，
//     标题 20 号主题色居中、内容 12 号 #50607A 居中，照片按顺序每区最多 4 张分摊（不足补占位框，总上限 19 张）
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

String _todayDot() {
  final d = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}.${p(d.month)}.${p(d.day)}';
}

class _PuzzlePageState extends State<PuzzlePage> {
  final picker = ImagePicker();
  final boundaryKey = GlobalKey();
  String template = '对比拼图';
  final List<XFile> photos = [];
  final Map<String, String> fieldValues = {};

  @override
  void initState() {
    super.initState();
    fieldValues['日期'] = _todayCn();
    fieldValues['保洁绿化服务'] = '清理积雪 清理垃圾';
    fieldValues['工程维修服务'] = '修卷帘门 工程维修';
    fieldValues['物业品质检查'] = '例行检查 保证质量';
    fieldValues['客服接待服务'] = '例行检查 保证质量';
    fieldValues['日常工作规划'] = '服务业主 提升品质内容';
  }

  bool get isWorkReport => template == '工作汇报拼图';
  bool get isMeeting => template == '会议';
  bool get isSupervision => template == '监理巡检';
  bool get isCompare => template == '对比拼图';
  bool get isDaily => template == '日常拼图';
  List<String> get inputFields {
    if (isWorkReport) return const ['汇报人', '日期', '天气', '检查总结', '问题描述', '问题详情'];
    if (isMeeting) return const ['主持人', '日期', '记录人', '参与人', '会议地点', '会议主题', '会议内容'];
    if (isSupervision) return const ['日期', '上午天气', '下午天气', '记录人', '审核人', '施工情况记录', '今日现场情况', '今日施工质量方面', '今日协调事项及重要事项'];
    if (isCompare) return const ['汇报人', '日期', '天气', '工作前', '工作后', '检查总结', '问题描述', '问题详情'];
    if (isDaily) return const ['汇报人', '日期', '天气', '保洁绿化服务', '工程维修服务', '物业品质检查', '客服接待服务', '日常工作规划'];
    return puzzleSpecs[template]?.fields ?? [];
  }

  List<String> get workItems => const ['检查总结', '问题描述', '问题详情'];
  List<String> get meetingTableRows => const ['记录人', '参与人', '会议地点', '会议主题', '会议内容'];
  List<String> get supervisionItems => const ['施工情况记录', '今日现场情况', '今日施工质量方面', '今日协调事项及重要事项'];
  List<String> get compareItems => const ['检查总结', '问题描述', '问题详情'];
  List<String> get dailySections => const ['保洁绿化服务', '工程维修服务', '物业品质检查', '客服接待服务', '日常工作规划'];
  Map<String, String> get dailyDefaults => const {
        '保洁绿化服务': '清理积雪 清理垃圾',
        '工程维修服务': '修卷帘门 工程维修',
        '物业品质检查': '例行检查 保证质量',
        '客服接待服务': '例行检查 保证质量',
        '日常工作规划': '服务业主 提升品质内容',
      };

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
      try {
        final docs = await getApplicationDocumentsDirectory();
        final galleryDir = Directory('${docs.path}/wm_photos');
        if (!await galleryDir.exists()) await galleryDir.create(recursive: true);
        await file.copy('${galleryDir.path}/puzzle_${DateTime.now().millisecondsSinceEpoch}.png');
      } catch (_) {}
      await Share.shareXFiles([XFile(file.path)], text: '拼图照片');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('拼图已生成，可在分享面板里保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败：$e')));
    }
  }

  // 导出 Word：标题 + 字段 + 照片按真实尺寸等比放进 docx（原版 puzzle_word 的同类做法），
  // 生成器在 lib/docx_export.dart，本地已用 LibreOffice 转 PDF 验过能打开、中文正常。
  Future<void> saveWord() async {
    try {
      final spec = puzzleSpecs[template];
      final images = <DocxImage>[];
      for (var i = 0; i < photos.length; i++) {
        final bytes = await File(photos[i].path).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final ext = photos[i].path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
        images.add(DocxImage(filename: 'image${i + 1}.$ext', bytes: bytes, width: frame.image.width, height: frame.image.height));
      }
      final docx = buildDocx(title: spec?.defaultTitle ?? template, fields: fieldValues, images: images);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/puzzle_${DateTime.now().millisecondsSinceEpoch}.docx');
      await file.writeAsBytes(docx);
      await Share.shareXFiles([XFile(file.path)], text: '拼图Word');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('拼图 Word 已生成，可在分享面板里保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出 Word 失败：$e')));
    }
  }

  // 导出 PDF：把当前拼图整页渲染成图片放进一页 PDF（原版 puzzle_pdf 的同类做法）。
  // PDF 里不直接排中文（标准字体不支持中文会乱码），中文标题/字段都在图片里，PDF 只做载体。
  Future<void> savePdf() async {
    try {
      final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final png = bytes.buffer.asUint8List();
      final doc = pw.Document();
      final image = pw.MemoryImage(png);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/puzzle_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(await doc.save());
      await Share.shareXFiles([XFile(file.path)], text: '拼图PDF');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('拼图 PDF 已生成，可在分享面板里保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出 PDF 失败：$e')));
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

  Widget _meetingHeader() {
    const contentColor = Color(0xFF232325);
    const titleColor = Color(0xFFA8A8A8);
    const lineColor = Color(0xFF232325);
    const themeColor = Color(0xFFFF371C);
    final host = fieldValues['主持人'] ?? '';
    final date = fieldValues['日期'] ?? _todayCn();
    final rows = meetingTableRows;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
      ]),
      const SizedBox(height: 5),
      const Text('会议纪要', textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 32, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(child: Text('主持人：$host', style: const TextStyle(fontSize: 14, color: contentColor))),
        Expanded(child: Text(date, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, color: contentColor))),
      ]),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Container(height: 2, color: themeColor)),
      const SizedBox(height: 8),
      // 带边框的表：左右 + 顶部 1px 线，行间 1px 线，标题 #A8A8A8、内容 #232325
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: lineColor, width: 1), right: BorderSide(color: lineColor, width: 1), top: BorderSide(color: lineColor, width: 1), bottom: BorderSide(color: lineColor, width: 1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.all(8),
              child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [TextSpan(text: '${rows[i]}   ', style: const TextStyle(color: titleColor)), TextSpan(text: fieldValues[rows[i]] ?? '')])),
            ),
            if (i < rows.length - 1) Container(height: 1, color: lineColor),
          ],
        ]),
      ),
      const SizedBox(height: 12),
    ]);
  }

  Widget _supervisionHeader() {
    const contentColor = Color(0xFF232325);
    const themeColor = Color(0xFF2E5BFF);
    // 原 layout 的 dateFormat 是 yyyy.MM.dd，输入框默认是中文日期时在这里转成点格式显示
    final rawDate = fieldValues['日期'] ?? _todayDot();
    final date = rawDate.replaceAll('年', '.').replaceAll('月', '.').replaceAll('日', '');
    Widget pair(String leftTitle, String rightTitle) {
      return Row(children: [
        Expanded(child: Padding(padding: const EdgeInsets.all(8), child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [TextSpan(text: '$leftTitle   ', style: const TextStyle(color: themeColor)), TextSpan(text: fieldValues[leftTitle] ?? '')])))),
        Container(width: 1, color: themeColor),
        Expanded(child: Padding(padding: const EdgeInsets.all(8), child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [TextSpan(text: '$rightTitle   ', style: const TextStyle(color: themeColor)), TextSpan(text: fieldValues[rightTitle] ?? '')])))),
      ]);
    }

    final items = supervisionItems;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
      ]),
      const SizedBox(height: 5),
      const Text('监理日志', textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 32, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: themeColor, width: 1), right: BorderSide(color: themeColor, width: 1), top: BorderSide(color: themeColor, width: 1), bottom: BorderSide(color: themeColor, width: 1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.all(8), child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [const TextSpan(text: '日期   ', style: TextStyle(color: themeColor)), TextSpan(text: date)]))),
          Container(height: 1, color: themeColor),
          pair('上午天气', '下午天气'),
          Container(height: 1, color: themeColor),
          pair('记录人', '审核人'),
          Container(height: 1, color: themeColor),
          for (int i = 0; i < items.length; i++) ...[
            Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(items[i], style: const TextStyle(fontSize: 14, color: themeColor)),
              const SizedBox(height: 2),
              Text(fieldValues[items[i]] ?? '', style: const TextStyle(fontSize: 14, color: contentColor)),
            ])),
            if (i < items.length - 1) Container(height: 1, color: themeColor),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Column(children: [
        Container(height: 2, color: themeColor),
        Container(height: 2, color: Colors.white),
        Container(height: 4, color: themeColor),
      ])),
      const SizedBox(height: 8),
    ]);
  }


  Widget _compareHeader() {
    const themeColor = Color(0xFF5076FF);
    const contentColor = Color(0xFF232325);
    final reporter = fieldValues['汇报人'] ?? '';
    final date = fieldValues['日期'] ?? _todayCn();
    final weather = fieldValues['天气'] ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
        const SizedBox(width: 8),
        Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
      ]),
      const SizedBox(height: 5),
      const Text('物业清洁', textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 40, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      const Text('现场清洁照片记录', textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 14)),
      const SizedBox(height: 8),
      RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [const TextSpan(text: '汇报人：', style: TextStyle(color: themeColor)), TextSpan(text: reporter)])),
      const SizedBox(height: 4),
      RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [const TextSpan(text: '日期：', style: TextStyle(color: themeColor)), TextSpan(text: date)])),
      const SizedBox(height: 4),
      RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: contentColor), children: [const TextSpan(text: '天气：', style: TextStyle(color: themeColor)), TextSpan(text: weather)])),
      const SizedBox(height: 8),
      for (final f in compareItems)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: const BoxDecoration(color: Color(0xFFF6F7FB)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(height: 1, color: themeColor),
            Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f, style: const TextStyle(fontSize: 14, color: themeColor)),
              const SizedBox(height: 2),
              Text((fieldValues[f] ?? '').isEmpty ? '点击输入内容' : fieldValues[f]!, style: TextStyle(fontSize: 14, color: (fieldValues[f] ?? '').isEmpty ? Colors.grey : contentColor)),
            ])),
          ]),
        ),
      Container(
        height: 30,
        margin: const EdgeInsets.only(left: 8, right: 8, top: 10),
        color: themeColor,
        child: Row(children: [
          const Expanded(child: Center(child: Text('工作前', style: TextStyle(color: Colors.white, fontSize: 15)))),
          Container(width: 1, color: Colors.white, margin: const EdgeInsets.symmetric(vertical: 5)),
          const Expanded(child: Center(child: Text('工作后', style: TextStyle(color: Colors.white, fontSize: 15)))),
        ]),
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _dailyHeader() {
    const themeColor = Color(0xFF2D38B9);
    const gridColor = Color(0xFFE73558);
    const sectionContentColor = Color(0xFF50607A);
    final date = fieldValues['日期'] ?? _todayCn();
    final reporter = fieldValues['汇报人'] ?? '张三';
    final weather = fieldValues['天气'] ?? '';
    final sections = dailySections;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        margin: const EdgeInsets.all(6),
        padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 110, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('品牌图片', style: TextStyle(fontSize: 12, color: Colors.grey))),
            const SizedBox(width: 16),
            Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
            Expanded(child: Text(date, textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, color: themeColor))),
          ]),
          Container(height: 2, color: themeColor, margin: const EdgeInsets.only(top: 11, bottom: 16)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(children: [
              const Text('物业周报', textAlign: TextAlign.center, style: TextStyle(color: themeColor, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 4), color: gridColor, child: const Text('本周工作汇报', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5))),
            ])),
            const SizedBox(width: 10),
            Expanded(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2), border: Border.all(color: gridColor, width: 1)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.all(8), child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: gridColor), children: [const TextSpan(text: '汇报人：', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: reporter)]))),
                  Container(height: 1, color: gridColor),
                  Padding(padding: const EdgeInsets.all(8), child: RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: gridColor), children: [const TextSpan(text: '天气：', style: TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: weather)]))),
                ]),
              ),
            ),
          ]),
        ]),
      ),
      for (int si = 0; si < sections.length; si++) ...[
        Container(
          margin: const EdgeInsets.fromLTRB(6, 10, 6, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300, width: 0.5)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(sections[si], textAlign: TextAlign.center, style: const TextStyle(color: themeColor, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(fieldValues[sections[si]] ?? dailyDefaults[sections[si]] ?? '', textAlign: TextAlign.center, style: const TextStyle(color: sectionContentColor, fontSize: 12)),
            const SizedBox(height: 8),
            // 该分区的照片：按顺序每区最多 4 张，不足补占位框
            Builder(builder: (_) {
              final start = si * 4;
              final end = (start + 4).clamp(0, photos.length);
              final slice = start < photos.length ? photos.sublist(start, end) : <XFile>[];
              final slots = List<Widget>.generate(4, (i) {
                if (i < slice.length) {
                  return Expanded(child: Padding(padding: const EdgeInsets.all(4), child: Image.file(File(slice[i].path), height: 110, fit: BoxFit.cover)));
                }
                return Expanded(child: Container(height: 110, margin: const EdgeInsets.all(4), alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0x0F3248BD), borderRadius: BorderRadius.circular(4)), child: const Text('添加照片', style: TextStyle(fontSize: 12, color: Colors.grey))));
              });
              return Column(children: [
                Row(children: slots.sublist(0, 2)),
                Row(children: slots.sublist(2, 4)),
              ]);
            }),
          ]),
        ),
      ],
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
              initialValue: f == '日期' ? fieldValues['日期'] : (isDaily ? (fieldValues[f] ?? dailyDefaults[f]) : null),
              onChanged: (v) => setState(() => fieldValues[f] = v),
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: pickMulti, child: Text('添加照片（已选 ${photos.length} 张）'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: photos.isEmpty ? null : save, child: const Text('生成拼图并分享'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: savePdf, child: const Text('导出拼图 PDF'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: saveWord, child: const Text('导出拼图 Word'))),
          ]),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: boundaryKey,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (isWorkReport) _workReportHeader(themeColor) else if (isMeeting) _meetingHeader() else if (isSupervision) _supervisionHeader() else if (isCompare) _compareHeader() else if (isDaily) _dailyHeader() else if (spec != null) _genericHeader(spec, themeColor),
                if (isDaily) ...[
                  if (photos.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('还没有照片，点上面添加照片'))),
                ] else if (isCompare && photos.length >= 2) ...[
                  Row(children: [
                    Expanded(child: Column(children: [Image.file(File(photos[0].path), height: 180, fit: BoxFit.cover), const SizedBox(height: 4), const Text('前', style: TextStyle(fontSize: 12, color: Colors.grey))])),
                    const SizedBox(width: 8),
                    Expanded(child: Column(children: [Image.file(File(photos[1].path), height: 180, fit: BoxFit.cover), const SizedBox(height: 4), const Text('后', style: TextStyle(fontSize: 12, color: Colors.grey))])),
                  ]),
                  const SizedBox(height: 8),
                  for (final p in photos.sublist(2)) ...[
                    Image.file(File(p.path), height: 220, fit: BoxFit.cover),
                    const SizedBox(height: 8),
                  ],
                ] else ...[
                  if (photos.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('还没有照片，点上面添加照片'))),
                  for (final p in photos) ...[
                    Image.file(File(p.path), height: 220, fit: BoxFit.cover),
                    const SizedBox(height: 8),
                  ],
                ],
                if (!isWorkReport && !isMeeting && !isSupervision && !isCompare && !isDaily && spec != null)
                  for (final f in spec.fields)
                    if ((fieldValues[f] ?? '').isNotEmpty)
                      Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0xFFF6F7FB), borderRadius: BorderRadius.circular(8)), child: Text('$f：${fieldValues[f]}', style: const TextStyle(fontSize: 14))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text('说明：多图拼图为干净重写版，头 + 字段 + 照片纵排，不含原厂图片、装饰、VIP、云端。工作汇报、会议纪要、监理日志、对比、日常拼图已按原 layout.xml 的头顺序、颜色、字号排版。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }
}
