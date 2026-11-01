import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 团队工作台：按 REA 挖到的原版模块清单重构的功能骨架（本地版）。
// 来源模块：TeamAttendanceWaterMarkWidget、团队水印统一标准、考勤最早/最晚拍照时间、
// 巡检打卡、右下角防伪码。本地版数据只存在本机，未接马克管理后台，不跨设备同步、不登录。

// 防伪码：由时间+地点算出的 8 位十六进制码，格式 MK-XXXX-XXXX，显示在水印条右下角。
String antiFraudCode(String seed) {
  var hash = 0x811c9dc5;
  for (final c in seed.codeUnits) {
    hash ^= c;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final hex = hash.toRadixString(16).padLeft(8, '0').toUpperCase();
  return 'MK-${hex.substring(0, 4)}-${hex.substring(4)}';
}

Future<String> loadTeamName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('wm_team_name') ?? '';
}

// 每次生成水印照片时记一条考勤：日期、时间、模板、地点、防伪码。
Future<void> recordAttendance({required String template, required String location, String antiFraud = ''}) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('wm_attendance') ?? '[]';
  final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  final now = DateTime.now();
  String p(int n) => n.toString().padLeft(2, '0');
  list.add({
    'date': '${now.year}-${p(now.month)}-${p(now.day)}',
    'time': '${p(now.hour)}:${p(now.minute)}:${p(now.second)}',
    'template': template,
    'location': location,
    'code': antiFraud,
  });
  await prefs.setString('wm_attendance', jsonEncode(list));
}

class WorkbenchPage extends StatefulWidget {
  const WorkbenchPage({super.key});
  @override
  State<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends State<WorkbenchPage> {
  String teamName = '';
  String teamNo = '';
  List<String> members = [];
  List<Map<String, dynamic>> attendance = [];
  List<Map<String, dynamic>> inspection = [];
  final teamNameCtrl = TextEditingController();
  final scheduleStartCtrl = TextEditingController(text: '09:00');
  final scheduleEndCtrl = TextEditingController(text: '18:00');
  String scheduleStart = '09:00';
  String scheduleEnd = '18:00';
  final memberCtrl = TextEditingController();
  final pointNameCtrl = TextEditingController();
  final pointLocCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      teamName = prefs.getString('wm_team_name') ?? '';
      teamNo = prefs.getString('wm_team_no') ?? '';
      teamNameCtrl.text = teamName;
      scheduleStart = prefs.getString('wm_schedule_start') ?? '09:00';
      scheduleEnd = prefs.getString('wm_schedule_end') ?? '18:00';
      scheduleStartCtrl.text = scheduleStart;
      scheduleEndCtrl.text = scheduleEnd;
      members = (jsonDecode(prefs.getString('wm_team_members') ?? '[]') as List).cast<String>();
      attendance = (jsonDecode(prefs.getString('wm_attendance') ?? '[]') as List).cast<Map<String, dynamic>>();
      inspection = (jsonDecode(prefs.getString('wm_inspection') ?? '[]') as List).cast<Map<String, dynamic>>();
    });
  }

  Future<void> _saveTeam() async {
    final prefs = await SharedPreferences.getInstance();
    final name = teamNameCtrl.text.trim();
    var no = teamNo;
    if (no.isEmpty && name.isNotEmpty) {
      var h = 0;
      for (final c in name.codeUnits) {
        h = (h * 31 + c) % 900000;
      }
      no = (100000 + h).toString();
    }
    await prefs.setString('wm_team_name', name);
    await prefs.setString('wm_team_no', no);
    await prefs.setString('wm_team_members', jsonEncode(members));
    if (mounted) {
      setState(() { teamName = name; teamNo = no; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('团队已保存，拍照水印会带上团队名')));
    }
  }

  Future<void> _saveInspection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wm_inspection', jsonEncode(inspection));
  }

  bool _nfcScanning = false;

  // NFC 打卡：把手机贴近标签，读到标签 ID 就记一条已打卡的巡检记录。
  Future<void> _nfcCheckIn() async {
    final available = await NfcManager.instance.isAvailable();
    if (!available) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此设备不支持 NFC 或未开启 NFC')));
      return;
    }
    setState(() => _nfcScanning = true);
    try {
      await NfcManager.instance.startSession(onDiscovered: (tag) async {
        final idData = tag.data['id'];
        String tagId;
        if (idData is List) {
          tagId = idData.map((e) => (e as int).toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
        } else {
          tagId = tag.data.toString();
        }
        final now = DateTime.now();
        String p(int n) => n.toString().padLeft(2, '0');
        setState(() {
          inspection.add({'name': 'NFC打卡', 'location': '标签 $tagId', 'checked': true, 'checkedTime': '${p(now.hour)}:${p(now.minute)}'});
        });
        await _saveInspection();
        await NfcManager.instance.stopSession();
        if (mounted) {
          setState(() => _nfcScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('NFC 打卡成功：$tagId')));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _nfcScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('NFC 扫描失败：$e')));
      }
    }
  }

  String _csvCell(String v) => '"${v.replaceAll('"', '""')}"';

  Future<void> _exportCsv(String filename, String content) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(content);
      await Share.shareXFiles([XFile(file.path)], text: filename);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  void _exportAttendanceSummary() {
    final grouped = _groupAttendance();
    final dates = grouped.keys.toList()..sort();
    final buf = StringBuffer('日期,上班时间,下班时间,照片数\n');
    for (final d in dates) {
      final list = grouped[d]!;
      buf.writeln([d, list.first['time'].toString(), list.last['time'].toString(), list.length.toString()].map((e) => _csvCell(e)).join(','));
    }
    _exportCsv('考勤统计.csv', buf.toString());
  }

  void _exportWatermarkData() {
    final buf = StringBuffer('日期,时间,模板,地点,防伪码\n');
    for (final r in attendance) {
      final code = (r['code'] ?? '') as String;
      buf.writeln([
        (r['date'] ?? '').toString(),
        (r['time'] ?? '').toString(),
        (r['template'] ?? '').toString(),
        (r['location'] ?? '').toString(),
        code.isNotEmpty ? code : antiFraudCode('${r['date']} ${r['time']}|${r['location']}'),
      ].map((e) => _csvCell(e)).join(','));
    }
    _exportCsv('水印数据.csv', buf.toString());
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wm_schedule_start', scheduleStartCtrl.text.trim());
    await prefs.setString('wm_schedule_end', scheduleEndCtrl.text.trim());
    setState(() {
      scheduleStart = scheduleStartCtrl.text.trim();
      scheduleEnd = scheduleEndCtrl.text.trim();
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('排班已保存')));
  }

  // 当天考勤状态：只按本机照片时间与排班比对
  String _dayStatus(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return '';
    final first = (list.first['time'] ?? '') as String;
    final last = (list.last['time'] ?? '') as String;
    final late = first.compareTo('$scheduleStart:00') > 0;
    final early = last.compareTo('$scheduleEnd:00') < 0;
    if (list.length == 1) return '仅一次打卡';
    if (late && early) return '迟到·早退';
    if (late) return '迟到';
    if (early) return '早退';
    return '正常';
  }

  // 考勤按日期分组：上班=当天最早拍照，下班=当天最晚拍照（原版规则）
  Map<String, List<Map<String, dynamic>>> _groupAttendance() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in attendance) {
      final d = (r['date'] ?? '') as String;
      map.putIfAbsent(d, () => []).add(r);
    }
    for (final list in map.values) {
      list.sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupAttendance();
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('团队工作台'),
          backgroundColor: const Color(0xFF2E5BFF),
          foregroundColor: Colors.white,
          bottom: const TabBar(tabs: [Tab(text: '团队'), Tab(text: '考勤'), Tab(text: '巡检')]),
        ),
        body: TabBarView(
          children: [
            // 团队
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('团队水印，统一拍照标准', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(controller: teamNameCtrl, decoration: const InputDecoration(labelText: '团队名称')),
                const SizedBox(height: 8),
                Text(teamNo.isEmpty ? '团队号：保存后自动生成' : '团队号：$teamNo'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: memberCtrl, decoration: const InputDecoration(labelText: '成员姓名'))),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final m = memberCtrl.text.trim();
                      if (m.isEmpty) return;
                      setState(() { members.add(m); memberCtrl.clear(); });
                      _saveTeam();
                    },
                    child: const Text('添加成员'),
                  ),
                ]),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _saveTeam, child: const Text('保存团队')),
                const SizedBox(height: 12),
                Text('成员（${members.length}人）', style: const TextStyle(fontWeight: FontWeight.bold)),
                for (var i = 0; i < members.length; i++)
                  ListTile(
                    title: Text(members[i]),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () { setState(() => members.removeAt(i)); _saveTeam(); },
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('本地版说明：团队数据只存在本机，未接马克管理后台，无法跨设备同步，也不需要登录。', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ),
            // 考勤
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('考勤规则：上班=当天最早拍照时间，下班=当天最晚拍照时间', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: scheduleStartCtrl, decoration: const InputDecoration(labelText: '排班上班（HH:mm）'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: scheduleEndCtrl, decoration: const InputDecoration(labelText: '排班下班（HH:mm）'))),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _saveSchedule, child: const Text('保存排班')),
                ]),
                const SizedBox(height: 8),
                Card(child: ListTile(title: Text('共 ${dates.length} 天 · ${attendance.length} 张照片'), subtitle: const Text('统计口径与原版一致：只按本机生成的水印照片统计'))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: ElevatedButton(onPressed: attendance.isEmpty ? null : _exportAttendanceSummary, child: const Text('导出考勤统计'))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(onPressed: attendance.isEmpty ? null : _exportWatermarkData, child: const Text('导出水印数据'))),
                ]),
                const SizedBox(height: 12),
                if (dates.isEmpty) const Text('还没有考勤记录，去拍一张带水印的照片就会记一条。'),
                for (final d in dates)
                  Card(
                    child: ListTile(
                      title: Text('$d  ${_dayStatus(grouped[d]!)}'),
                      subtitle: Text('上班 ${grouped[d]!.first['time']}  ·  下班 ${grouped[d]!.last['time']}  ·  照片 ${grouped[d]!.length} 张  ·  排班 $scheduleStart-$scheduleEnd'),
                    ),
                  ),
              ],
            ),
            // 巡检
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('巡检打卡：先加巡检点，到点拍照后勾选', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(controller: pointNameCtrl, decoration: const InputDecoration(labelText: '巡检点名称')),
                TextField(controller: pointLocCtrl, decoration: const InputDecoration(labelText: '巡检点地点')),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    final n = pointNameCtrl.text.trim();
                    if (n.isEmpty) return;
                    setState(() {
                      inspection.add({'name': n, 'location': pointLocCtrl.text.trim(), 'checked': false, 'checkedTime': ''});
                      pointNameCtrl.clear();
                      pointLocCtrl.clear();
                    });
                    _saveInspection();
                  },
                  child: const Text('添加巡检点'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _nfcScanning ? null : _nfcCheckIn,
                  child: Text(_nfcScanning ? '把手机贴近 NFC 标签…' : 'NFC 扫标签打卡'),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < inspection.length; i++)
                  Card(
                    child: ListTile(
                      leading: Checkbox(
                        value: inspection[i]['checked'] as bool? ?? false,
                        onChanged: (v) {
                          final now = DateTime.now();
                          String p(int n) => n.toString().padLeft(2, '0');
                          setState(() {
                            inspection[i]['checked'] = v ?? false;
                            inspection[i]['checkedTime'] = v == true ? '${p(now.hour)}:${p(now.minute)}' : '';
                          });
                          _saveInspection();
                        },
                      ),
                      title: Text((inspection[i]['name'] ?? '') as String),
                      subtitle: Text([if (((inspection[i]['location'] ?? '') as String).isNotEmpty) (inspection[i]['location'] as String), if (((inspection[i]['checkedTime'] ?? '') as String).isNotEmpty) '打卡 ${(inspection[i]['checkedTime'] as String)}'].join(' · ')),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () { setState(() => inspection.removeAt(i)); _saveInspection(); },
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('说明：考勤水印、物业巡检水印、宣传水印在原版中不支持编辑，本页巡检点也只做打卡记录，不改水印内容。', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
