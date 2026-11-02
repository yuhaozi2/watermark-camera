import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'puzzle_page.dart';
import 'live_camera_page.dart';
import 'video_watermark_page.dart';
import 'workbench_page.dart';
import 'gallery_page.dart';
import 'package:image/image.dart' as imgLib;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// 定位后自动补全：地点名称用 Nominatim 逆地理编码（公开服务，免 key），
// 天气用 Open-Meteo（公开服务，免 key）；原版天气来源是彩云天气，那个要 key，这里先用公开服务顶上。
String weatherCodeChinese(int code) {
  if (code == 0) return '晴';
  if (code == 1 || code == 2) return '多云';
  if (code == 3) return '阴';
  if (code == 45 || code == 48) return '雾';
  if (code >= 51 && code <= 55) return '毛毛雨';
  if (code >= 61 && code <= 65) return '雨';
  if (code >= 71 && code <= 75) return '雪';
  if (code >= 80 && code <= 82) return '阵雨';
  if (code == 95) return '雷阵雨';
  return '多云';
}

Future<Map<String, String>> fetchPlaceAndWeather(double lat, double lng) async {
  final result = <String, String>{};
  try {
    final geo = await http.get(
      Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=18&addressdetails=1'),
      headers: {'User-Agent': 'watermark-camera/1.0'},
    ).timeout(const Duration(seconds: 10));
    if (geo.statusCode == 200) {
      final data = jsonDecode(geo.body) as Map<String, dynamic>;
      final addr = (data['address'] as Map<String, dynamic>?) ?? {};
      final parts = <String>[];
      for (final k in ['state', 'city', 'town', 'village', 'suburb', 'quarter', 'road']) {
        final v = (addr[k] ?? '').toString();
        if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
      }
      final name = (data['name'] ?? '').toString();
      if (name.isNotEmpty && !parts.contains(name)) parts.add(name);
      if (parts.isNotEmpty) result['place'] = parts.join('');
    }
  } catch (_) {}
  try {
    final w = await http.get(
      Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lng&current=temperature_2m,weather_code&timezone=auto'),
    ).timeout(const Duration(seconds: 10));
    if (w.statusCode == 200) {
      final data = jsonDecode(w.body) as Map<String, dynamic>;
      final cur = (data['current'] as Map<String, dynamic>?) ?? {};
      final temp = cur['temperature_2m'];
      final code = cur['weather_code'];
      if (temp != null && code != null) {
        result['weather'] = '${weatherCodeChinese((code as num).toInt())} ${(temp as num).toStringAsFixed(0)}°C';
      }
    }
  } catch (_) {}
  return result;
}

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
      ['汇报人', '日期', '天气', '工作前', '工作后', '检查总结', '问题描述', '问题详情'],
      [['汇报人'], ['日期'], ['天气'], ['工作前', '工作后']]),
  '会议': TemplateSpec(0xFFFF371C, '会议纪要', '',
      ['主持人', '日期', '记录人', '参与人', '会议地点', '会议主题', '会议内容'],
      [['主持人', '日期'], ['记录人'], ['参与人'], ['会议地点']]),
  '监理巡检': TemplateSpec(0xFF2E5BFF, '监理日志', '',
      ['日期', '上午天气', '下午天气', '记录人', '审核人', '施工情况记录', '今日现场情况', '今日施工质量方面', '今日协调事项及重要事项'],
      [['日期'], ['上午天气', '下午天气'], ['记录人', '审核人']]),
  '工作汇报拼图': TemplateSpec(0xFF2E5BFF, '工作汇报', '工作现场照片汇总整理',
      ['汇报人', '日期', '天气', '检查总结', '问题描述', '问题详情'],
      [['汇报人', '日期', '天气']]),
  '日常拼图': TemplateSpec(0xFF2D38B9, '物业周报', '本周工作汇报',
      ['汇报人', '日期', '天气', '保洁绿化服务', '工程维修服务', '物业品质检查', '客服接待服务', '日常工作规划'],
      [['汇报人', '日期'], ['天气']]),
};

// 单张水印模板的功能字段（非原包提取，原包水印包只有图片、无模板 JSON，
// 故按原版同类模板常见标签重构，不复制原图；每个模板的标签顺序即水印条里的显示顺序）
const singleSpecs = {
  '时间地点': TemplateSpec(0xFF2E5BFF, '时间地点', '', ['地点', '经纬度', '天气'], []),
  '打卡考勤': TemplateSpec(0xFF2E5BFF, '打卡考勤', '', ['姓名', '部门', '考勤类型', '地点'], []),
  '工作记录': TemplateSpec(0xFF2E5BFF, '工作记录', '', ['项目', '工单', '工作内容', '负责人', '地点'], []),
  '工程项目': TemplateSpec(0xFF2E5BFF, '工程项目', '', ['项目名称', '施工单位', '监理单位', '施工部位', '地点'], []),
  '物业': TemplateSpec(0xFF5076FF, '物业', '', ['小区', '区域', '汇报人', '地点'], []),
  '销售': TemplateSpec(0xFFFF371C, '销售', '', ['门店', '销售员', '客户', '地点'], []),
  '电力': TemplateSpec(0xFF2E5BFF, '电力', '', ['变电站', '设备', '操作人', '地点'], []),
  '团队品牌': TemplateSpec(0xFF2E5BFF, '团队品牌', '', ['品牌名称', '团队', '地点'], []),
};

TemplateSpec? specFor(String t) => puzzleSpecs[t] ?? singleSpecs[t];

// 取一个标签的值：优先用户在表单里填的，其次是定位结果
// 地点优先显示解析出的地点名称，经纬度显示坐标
String? tagValue(Map<String, String> fieldValues, String field, String locationText, {String placeText = ''}) {
  final v = fieldValues[field];
  if (v != null && v.isNotEmpty) return v;
  if (field == '地点' && placeText.isNotEmpty) return placeText;
  if ((field == '地点' || field == '经纬度') && locationText.isNotEmpty) return locationText;
  return null;
}

// 单张水印条的全部行：标题、时间在前，之后按模板标签顺序排列，不重复、不留空行。
// 取景页和成图页共用这个函数，所见即所得。
List<String> buildWatermarkLines({
  required String template,
  required String timeText,
  required Map<String, String> fieldValues,
  required String projectText,
  required String locationText,
  required String customText,
  required String remark,
  required String weatherText,
  String teamName = '',
  String placeText = '',
}) {
  if (template == '简洁水印') {
    return [timeText, if (locationText.isNotEmpty) '📍 $locationText'];
  }
  final spec = specFor(template);
  final lines = <String>[spec?.defaultTitle ?? template];
  if (teamName.isNotEmpty) lines.add('团队：$teamName');
  lines.add(timeText);
  if (spec != null) {
    for (final f in spec.fields) {
      final v = tagValue(fieldValues, f, locationText, placeText: placeText);
      if (v == null || v.isEmpty) continue;
      if (f == '地点') {
        lines.add('📍 $v');
      } else {
        lines.add('$f：$v');
      }
    }
  }
  final hasWeatherTag = spec?.fields.contains('天气') ?? false;
  if (weatherText.isNotEmpty && !hasWeatherTag) lines.add('天气：$weatherText');
  final hasProjectTag = spec?.fields.any((f) => f == '项目' || f == '项目名称') ?? false;
  if (projectText.isNotEmpty && !hasProjectTag) lines.add('项目：$projectText');
  final hasLocationTag = spec?.fields.any((f) => f == '地点' || f == '经纬度') ?? false;
  if (!hasLocationTag && placeText.isNotEmpty) lines.add('📍 $placeText');
  if (!hasLocationTag && placeText.isEmpty && locationText.isNotEmpty) lines.add('📍 $locationText');
  if (customText.isNotEmpty) lines.add(customText);
  if (remark.isNotEmpty) lines.add(remark);
  return lines;
}

// 单张水印条：底部通栏白底 + 主题色竖条 + 大号加粗时间 + 右侧 Logo 占位（灰色框，不用原厂图）。
// 简洁水印不画白条，只在照片上叠加带阴影的白字。
Widget buildWatermarkBar({
  required List<String> lines,
  required Color themeColor,
  required double fontSize,
  required double opacity,
  required bool simple,
  String antiFraudCode = '',
  String brandImagePath = '',
}) {
  if (lines.isEmpty) return const SizedBox.shrink();
  if (simple) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(line, style: TextStyle(color: Colors.white, fontSize: fontSize + 2, height: 1.5, shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))])),
          if (antiFraudCode.isNotEmpty) Text('防伪码 $antiFraudCode', style: TextStyle(color: Colors.white70, fontSize: fontSize - 1, height: 1.5, shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))])),
        ],
      ),
    );
  }
  final title = lines.first;
  // 团队行（如果有）在标题之后、时间之前；时间是除标题、团队行外的第一行
  var timeIndex = 1;
  var restStart = 2;
  if (lines.length > 2 && lines[1].startsWith('团队：')) {
    timeIndex = 2;
    restStart = 3;
  }
  final time = lines.length > timeIndex ? lines[timeIndex] : '';
  final rest = lines.length > restStart ? lines.sublist(restStart) : <String>[];
  final teamLine = timeIndex == 2 ? lines[1] : '';
  return Container(
    width: double.infinity,
    color: Colors.white.withOpacity(opacity.clamp(0.3, 1.0)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 4, color: themeColor, constraints: const BoxConstraints(minHeight: 56)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(color: themeColor, fontSize: fontSize, fontWeight: FontWeight.bold, height: 1.4)),
                if (teamLine.isNotEmpty) Text(teamLine, style: TextStyle(color: const Color(0xFF50607A), fontSize: fontSize, height: 1.4)),
                if (time.isNotEmpty) Text(time, style: TextStyle(color: const Color(0xFF232325), fontSize: fontSize + 8, fontWeight: FontWeight.bold, height: 1.4)),
                for (final line in rest) Text(line, style: TextStyle(color: const Color(0xFF50607A), fontSize: fontSize, height: 1.5)),
                if (antiFraudCode.isNotEmpty) Text('防伪码 $antiFraudCode · 已验证真实性', style: TextStyle(color: Colors.grey, fontSize: fontSize - 2, height: 1.5)),
              ],
            ),
          ),
        ),
        if (brandImagePath.isNotEmpty)
          Container(
            width: 40, height: 40, margin: const EdgeInsets.only(right: 10, top: 10),
            child: Image.file(
              File(brandImagePath),
              width: 40, height: 40, fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(alignment: Alignment.center, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey))),
            ),
          )
        else
          Container(
            width: 40, height: 40, margin: const EdgeInsets.only(right: 10, top: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
            child: const Text('Logo', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ),
      ],
    ),
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.6)..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

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
  String placeText = '';
  String remark = '';
  String weatherText = '';
  String projectText = '';
  String position = '左下';
  String timeText = '';
  String teamName = '';
  String brandLogoPath = '';
  Timer? _clock;
  final Map<String, String> fieldValues = {};
  Color watermarkColor = Colors.white;
  double watermarkSize = 13;
  double watermarkOpacity = 0.92;
  String ratio = '4:3';
  bool showGrid = false;
  String photoFilter = '原图';
  // 编辑滑杆：动了滑杆就进入自定义效果（芯片点一下会把滑杆归零，恢复该滤镜）
  double editBrightness = 0; // -50..50，直接做矩阵偏移
  double editContrast = 1.0; // 0.5..1.5
  double editSaturation = 1.0; // 0..2
  bool get _hasCustomEdit => editBrightness != 0 || editContrast != 1.0 || editSaturation != 1.0;

  // 4x5 颜色矩阵相乘（最后一行固定 0,0,0,0,1）
  List<double> _mulMatrix(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 5; c++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[r * 5 + k] * b[k * 5 + c];
        }
        if (c == 4) sum += a[r * 5 + 4];
        out[r * 5 + c] = sum;
      }
    }
    return out;
  }

  List<double> get _customEditMatrix {
    const lumR = 0.299, lumG = 0.587, lumB = 0.114;
    final s = editSaturation;
    final sat = <double>[
      lumR * (1 - s) + s, lumG * (1 - s), lumB * (1 - s), 0, 0,
      lumR * (1 - s), lumG * (1 - s) + s, lumB * (1 - s), 0, 0,
      lumR * (1 - s), lumG * (1 - s), lumB * (1 - s) + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
    final c = editContrast;
    final con = <double>[
      c, 0, 0, 0, (1 - c) * 128,
      0, c, 0, 0, (1 - c) * 128,
      0, 0, c, 0, (1 - c) * 128,
      0, 0, 0, 1, 0,
    ];
    final b = editBrightness;
    final bri = <double>[
      1, 0, 0, 0, b,
      0, 1, 0, 0, b,
      0, 0, 1, 0, b,
      0, 0, 0, 1, 0,
    ];
    return _mulMatrix(bri, _mulMatrix(con, sat));
  }

  // 照片滤镜：在预览图上套 ColorFiltered，生成时 RepaintBoundary 一并烧入成图
  ColorFilter? get photoColorFilter {
    if (_hasCustomEdit) return ColorFilter.matrix(_customEditMatrix);
    switch (photoFilter) {
      case '黑白':
        return const ColorFilter.matrix(<double>[0.299, 0.587, 0.114, 0, 0, 0.299, 0.587, 0.114, 0, 0, 0.299, 0.587, 0.114, 0, 0, 0, 0, 0, 1, 0]);
      case '暖色':
        return const ColorFilter.matrix(<double>[1.1, 0, 0, 0, 10, 0, 1.05, 0, 0, 5, 0, 0, 0.9, 0, 0, 0, 0, 0, 1, 0]);
      case '冷色':
        return const ColorFilter.matrix(<double>[0.9, 0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 0, 1.15, 0, 10, 0, 0, 0, 1, 0]);
      default:
        return null;
    }
  }

  // 旋转 90°：用 image 包真转出一张新文件，原图不动，预览和生成都用转后的版本
  Future<void> rotateImage() async {
    final src = image;
    if (src == null) return;
    try {
      final bytes = await src.readAsBytes();
      final decoded = imgLib.decodeImage(bytes);
      if (decoded == null) return;
      final rotated = imgLib.copyRotate(decoded, angle: 90);
      final dir = await getTemporaryDirectory();
      final isPng = src.path.toLowerCase().endsWith('.png');
      final out = File('${dir.path}/rotated_${DateTime.now().millisecondsSinceEpoch}.${isPng ? 'png' : 'jpg'}');
      await out.writeAsBytes(isPng ? imgLib.encodePng(rotated) : imgLib.encodeJpg(rotated, quality: 92));
      if (mounted) setState(() => image = out);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('旋转失败：$e')));
    }
  }

  // 地点是经纬度时，在浏览器地图里打开该点（用公开地图链接，不用原厂地图 SDK）
  Future<void> openMap() async {
    final parts = locationText.split(',');
    if (parts.length != 2) return;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void initState() {
    super.initState();
    timeText = formatNow();
    loadTeamName().then((v) { if (mounted) setState(() => teamName = v); });
    loadBrandLogoPath().then((v) { if (mounted) setState(() => brandLogoPath = v); });
    // 取景和预览里的时间每秒刷新，拍到的就是当前时间，不是打开页面的时间
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => timeText = formatNow());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
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
    final coord = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    setState(() => locationText = coord);
    // 定位成功后顺手补地点名称和天气（公开服务，失败就只留经纬度，不报错打断拍照）
    final extra = await fetchPlaceAndWeather(pos.latitude, pos.longitude);
    if (mounted) {
      setState(() {
        if ((extra['place'] ?? '').isNotEmpty) placeText = extra['place']!;
        if ((extra['weather'] ?? '').isNotEmpty) weatherText = extra['weather']!;
      });
      if ((extra['place'] ?? '').isNotEmpty || (extra['weather'] ?? '').isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已补全：${extra['place'] ?? ''} ${extra['weather'] ?? ''}'.trim())));
      }
    }
  }

  List<String> lines() => buildWatermarkLines(
        template: template,
        timeText: timeText,
        fieldValues: fieldValues,
        projectText: projectText,
        locationText: locationText,
        customText: customText,
        remark: remark,
        weatherText: weatherText,
        teamName: teamName,
        placeText: placeText,
      );

  Future<void> save() async {
    try {
      final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/watermark_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      // 同步存一份到本地相册目录，App 里“相册”随时能翻出来（存档失败不影响分享）
      try {
        final docs = await getApplicationDocumentsDirectory();
        final galleryDir = Directory('${docs.path}/wm_photos');
        if (!await galleryDir.exists()) await galleryDir.create(recursive: true);
        await file.copy('${galleryDir.path}/watermark_${DateTime.now().millisecondsSinceEpoch}.png');
      } catch (_) {}
      await recordAttendance(template: template, location: locationText, antiFraud: antiFraudCode('$timeText|$locationText'));
      await Share.shareXFiles([XFile(file.path)], text: '水印照片');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已生成，可在分享面板里保存到相册')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生成失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBottom = position.contains('下');
    final spec = specFor(template);
    final isPuzzle = puzzleSpecs.containsKey(template);
    final themeColor = spec != null ? Color(spec.themeColor) : Colors.blue;
    // 默认用模板主题色；用户在下面选了颜色，就用选的颜色做时间与竖条
    final barTheme = watermarkColor == Colors.white ? themeColor : watermarkColor;
    final previewHeight = ratio == '16:9' ? 220.0 : ratio == '1:1' ? 360.0 : ratio == '3:4' ? 420.0 : 360.0;
    return Scaffold(
      appBar: AppBar(title: Text('水印相机 · ${spec?.defaultTitle ?? template}'), backgroundColor: themeColor, foregroundColor: Colors.white,
        actions: [
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PuzzlePage())), child: const Text('拼图模式', style: TextStyle(color: Colors.white))),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GalleryPage())), child: const Text('相册', style: TextStyle(color: Colors.white))),
          TextButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkbenchPage()));
              final v = await loadTeamName();
              final logo = await loadBrandLogoPath();
              if (mounted) setState(() { teamName = v; brandLogoPath = logo; });
            },
            child: const Text('工作台', style: TextStyle(color: Colors.white)),
          ),
        ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          RepaintBoundary(
            key: boundaryKey,
            child: Container(
              height: previewHeight,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(children: [
                  if (image != null)
                    Positioned.fill(child: photoColorFilter == null ? Image.file(image!, fit: BoxFit.cover) : ColorFiltered(colorFilter: photoColorFilter!, child: Image.file(image!, fit: BoxFit.cover)))
                  else
                    const Center(child: Text('还没有照片\n点下面实时拍照或导入', textAlign: TextAlign.center)),
                  if (showGrid) const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GridPainter()))),
                  if (image != null)
                    Positioned(
                      left: 0, right: 0,
                      top: isBottom ? null : 0, bottom: isBottom ? 0 : null,
                      child: buildWatermarkBar(
                        lines: lines(),
                        themeColor: barTheme,
                        fontSize: watermarkSize,
                        opacity: watermarkOpacity,
                        simple: template == '简洁水印',
                        antiFraudCode: antiFraudCode('$timeText|$locationText'),
                        brandImagePath: brandLogoPath,
                      ),
                    ),
                ]),
              ),
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
          TextField(decoration: const InputDecoration(labelText: '项目 / 工单'), onChanged: (v) => setState(() => projectText = v)),
          TextField(decoration: const InputDecoration(labelText: '水印文字'), onChanged: (v) => setState(() => customText = v)),
          Row(children: [
            Expanded(child: TextField(decoration: const InputDecoration(labelText: '经纬度（定位后自动填）'), controller: TextEditingController(text: locationText), onChanged: (v) => setState(() => locationText = v))),
            TextButton(onPressed: locate, child: const Text('定位')),
          ]),
          TextField(decoration: const InputDecoration(labelText: '地点名称（定位后自动解析，可手改）'), controller: TextEditingController(text: placeText), onChanged: (v) => setState(() => placeText = v)),
          TextField(decoration: const InputDecoration(labelText: '天气（定位后自动填，可手改）'), controller: TextEditingController(text: weatherText), onChanged: (v) => setState(() => weatherText = v)),
          TextField(decoration: const InputDecoration(labelText: '备注（人员等）'), onChanged: (v) => setState(() => remark = v)),
          const SizedBox(height: 8),
          const Text('水印位置'),
          Wrap(spacing: 8, children: [
            for (final p in ['左下', '右下', '左上', '右上'])
              ChoiceChip(label: Text(p), selected: position == p, onSelected: (_) => setState(() => position = p)),
          ]),
          const SizedBox(height: 8),
          const Text('水印主题色（时间与竖条）'),
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
          Row(children: [
            const Text('滤镜'),
            const SizedBox(width: 8),
            for (final f in ['原图', '黑白', '暖色', '冷色'])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(f), selected: photoFilter == f && !_hasCustomEdit, onSelected: (_) => setState(() { photoFilter = f; editBrightness = 0; editContrast = 1.0; editSaturation = 1.0; })),
              ),
          ]),
          Row(children: [
            const Text('编辑'),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: image == null ? null : rotateImage, child: const Text('旋转 90°')),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() { photoFilter = '原图'; editBrightness = 0; editContrast = 1.0; editSaturation = 1.0; }), child: const Text('恢复原图效果')),
          ]),
          Row(children: [const Text('亮度'), Expanded(child: Slider(value: editBrightness, min: -50, max: 50, onChanged: (v) => setState(() => editBrightness = v))), Text(editBrightness.toStringAsFixed(0))]),
          Row(children: [const Text('对比度'), Expanded(child: Slider(value: editContrast, min: 0.5, max: 1.5, onChanged: (v) => setState(() => editContrast = v))), Text(editContrast.toStringAsFixed(2))]),
          Row(children: [const Text('饱和度'), Expanded(child: Slider(value: editSaturation, min: 0, max: 2, onChanged: (v) => setState(() => editSaturation = v))), Text(editSaturation.toStringAsFixed(2))]),
          const Text('说明：滤镜和编辑滑杆的效果在预览里就能看到，生成时一并烧进成图；旋转会真转出一张新图，原图不动。', style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (locationText.contains(','))
            TextButton(onPressed: openMap, child: const Text('在地图上查看定位点')),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              final file = await Navigator.push<File>(
                context,
                MaterialPageRoute(builder: (_) => LiveCameraPage(
                  template: template,
                  fieldValues: Map.of(fieldValues),
                  projectText: projectText,
                  locationText: locationText,
                  customText: customText,
                  remark: remark,
                  weatherText: weatherText,
                  teamName: teamName,
                  placeText: placeText,
                  brandLogoPath: brandLogoPath,
                )),
              );
              if (file != null && mounted) setState(() { image = file; timeText = formatNow(); });
            },
            child: const Text('实时拍照（取景里就带水印）'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VideoWatermarkPage(
                  template: template,
                  fieldValues: Map.of(fieldValues),
                  projectText: projectText,
                  locationText: locationText,
                  customText: customText,
                  remark: remark,
                  weatherText: weatherText,
                  teamName: teamName,
                  placeText: placeText,
                  brandLogoPath: brandLogoPath,
                )),
              );
            },
            child: const Text('视频水印（录像+烧入）'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: () => pick(ImageSource.camera), child: const Text('系统相机'))),
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
