import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'watermark_camera_page.dart';
import 'workbench_page.dart';

// 视频水印页：取景里底部就叠着同一条水印，录完后把水印条渲染成图片，
// 用 ffmpeg 的 overlay 滤镜按视频宽度等比放大、贴在视频底部烧进去，再分享成片。
// 编码用内置 mpeg4（min 版不带 libx264），这样包体不会因为全量 ffmpeg 库膨胀到无法直接下载。
// 不用 drawtext（不需要字体文件），水印长什么样、烧进去就是什么样。
class VideoWatermarkPage extends StatefulWidget {
  final String template;
  final Map<String, String> fieldValues;
  final String projectText;
  final String locationText;
  final String customText;
  final String remark;
  final String weatherText;
  final String teamName;
  final String placeText;
  const VideoWatermarkPage({
    super.key,
    required this.template,
    required this.fieldValues,
    required this.projectText,
    required this.locationText,
    required this.customText,
    required this.remark,
    required this.weatherText,
    this.teamName = '',
    this.placeText = '',
  });
  @override
  State<VideoWatermarkPage> createState() => _VideoWatermarkPageState();
}

class _VideoWatermarkPageState extends State<VideoWatermarkPage> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  String _error = '';
  String _timeText = '';
  String _locationText = '';
  String _placeText = '';
  Timer? _clock;
  Timer? _recordTimer;
  bool _recording = false;
  bool _processing = false;
  int _recordSeconds = 0;
  final barKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _timeText = formatNow();
    _locationText = widget.locationText;
    _placeText = widget.placeText;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _timeText = formatNow());
    });
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _error = '没有找到可用相机');
        return;
      }
      await _startCamera(_cameraIndex);
    } catch (e) {
      if (mounted) setState(() => _error = '相机初始化失败：$e，请检查相机权限');
    }
  }

  Future<void> _startCamera(int index) async {
    final old = _controller;
    await old?.dispose();
    final controller = CameraController(_cameras[index], ResolutionPreset.high, enableAudio: true);
    try {
      await controller.initialize();
    } catch (e) {
      if (mounted) setState(() => _error = '相机初始化失败：$e');
      return;
    }
    if (mounted) setState(() { _controller = controller; _error = ''; });
  }

  Future<void> _locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('定位权限被拒，请回主页面手填地点')));
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    if (mounted) setState(() => _locationText = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
    final extra = await fetchPlaceAndWeather(pos.latitude, pos.longitude);
    if (mounted && (extra['place'] ?? '').isNotEmpty) setState(() => _placeText = extra['place']!);
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.startVideoRecording();
      setState(() { _recording = true; _recordSeconds = 0; });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('开始录制失败：$e')));
    }
  }

  Future<void> _stopAndBurn() async {
    final controller = _controller;
    if (controller == null) return;
    XFile video;
    try {
      video = await controller.stopVideoRecording();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('停止录制失败：$e')));
      return;
    }
    _recordTimer?.cancel();
    setState(() { _recording = false; _processing = true; });
    try {
      // 1. 把当前水印条渲染成图片（取景里看到的同一条）
      final boundary = barKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw '水印条渲染失败';
      final dir = await getTemporaryDirectory();
      final barFile = File('${dir.path}/wm_bar_${DateTime.now().millisecondsSinceEpoch}.png');
      await barFile.writeAsBytes(bytes.buffer.asUint8List());
      // 2. 探视频宽度，水印条按视频宽度等比放大
      var videoWidth = 0;
      try {
        final probe = await FFprobeKit.getMediaInformation(video.path);
        final info = probe.getMediaInformation();
        if (info != null) {
          for (final s in info.getStreams()) {
            if (s.getWidth() != null && s.getWidth()! > 0) { videoWidth = s.getWidth()!; break; }
          }
        }
      } catch (_) {}
      final outPath = '${dir.path}/wm_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final filter = videoWidth > 0
          ? '[1:v]scale=$videoWidth:-1[wm];[0:v][wm]overlay=0:H-h'
          : '[0:v][1:v]overlay=0:H-h';
      final command = "-y -i ${video.path} -i ${barFile.path} -filter_complex $filter -c:v mpeg4 -q:v 3 -c:a copy $outPath";
      final session = await FFmpegKit.execute(command);
      final rc = await session.getReturnCode();
      final ok = ReturnCode.isSuccess(rc) && await File(outPath).exists();
      if (!mounted) return;
      setState(() => _processing = false);
      if (ok) {
        await Share.shareXFiles([XFile(outPath)], text: '水印视频');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('水印已烧进视频，可在分享面板里保存')));
      } else {
        // 烧录失败也不丢原片：把原视频分享出去，并告诉用户原因
        final logs = await session.getOutput();
        await Share.shareXFiles([XFile(video.path)], text: '原视频（水印烧录失败）');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('烧录失败，已分享原视频：${(logs ?? '').split('\n').last}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('处理失败：$e')));
      }
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _recordTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  String get _recordTime {
    final m = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final spec = specFor(widget.template);
    final themeColor = spec != null ? Color(spec.themeColor) : Colors.blue;
    final lines = buildWatermarkLines(
      template: widget.template,
      timeText: _timeText,
      fieldValues: widget.fieldValues,
      projectText: widget.projectText,
      locationText: _locationText,
      customText: widget.customText,
      remark: widget.remark,
      weatherText: widget.weatherText,
      teamName: widget.teamName,
      placeText: _placeText,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_recording ? '录制中 $_recordTime' : '视频水印 · ${spec?.defaultTitle ?? widget.template}'),
        backgroundColor: _recording ? Colors.red : themeColor,
        foregroundColor: Colors.white,
        actions: [TextButton(onPressed: _locate, child: const Text('定位', style: TextStyle(color: Colors.white)))],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_controller != null && _controller!.value.isInitialized)
                  Positioned.fill(child: CameraPreview(_controller!))
                else if (_error.isNotEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center)))
                else
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                if (_recording)
                  const Positioned(top: 12, left: 12, child: Row(children: [Icon(Icons.circle, color: Colors.red, size: 14), SizedBox(width: 6), Text('录制中', style: TextStyle(color: Colors.white)) ])),
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: RepaintBoundary(
                    key: barKey,
                    child: buildWatermarkBar(
                      lines: lines,
                      themeColor: themeColor,
                      fontSize: 13,
                      opacity: 0.92,
                      simple: widget.template == '简洁水印',
                      antiFraudCode: antiFraudCode('$_timeText|$_locationText'),
                    ),
                  ),
                ),
                if (_processing)
                  const Positioned.fill(child: ColoredBox(color: Color(0x88000000), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.white), SizedBox(height: 12), Text('正在把水印烧进视频…', style: TextStyle(color: Colors.white))])))),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: (_cameras.length > 1 && !_recording) ? () { _cameraIndex = (_cameraIndex + 1) % _cameras.length; _startCamera(_cameraIndex); } : null,
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),
                  GestureDetector(
                    onTap: _processing ? null : (_recording ? _stopAndBurn : _startRecording),
                    child: Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: _recording ? Colors.red : themeColor),
                      child: Icon(_recording ? Icons.stop : Icons.videocam, color: Colors.white, size: 32),
                    ),
                  ),
                  IconButton(
                    onPressed: _recording ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('点红点开始录制，再点一次停止，底部水印条会自动烧进视频', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }
}
