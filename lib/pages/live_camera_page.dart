import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'watermark_camera_page.dart';
import 'workbench_page.dart';

// 实时取景页：打开就是相机取景，水印条直接叠在取景画面底部，
// 时间每秒刷新、定位可手动刷新，拍下的照片回到主页面后套用同一条水印生成。
class LiveCameraPage extends StatefulWidget {
  final String template;
  final Map<String, String> fieldValues;
  final String projectText;
  final String locationText;
  final String customText;
  final String remark;
  final String weatherText;
  final String teamName;
  final String placeText;
  final String brandLogoPath;
  final String photographerName;
  final String altitudeText;
  final String placeNameText;
  final String placeTitleOverride;
  final bool originalStyle;
  const LiveCameraPage({
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
    this.brandLogoPath = '',
    this.photographerName = '',
    this.altitudeText = '',
    this.placeNameText = '',
    this.placeTitleOverride = '',
    this.originalStyle = true,
  });
  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  String _error = '';
  String _timeText = '';
  String _locationText = '';
  String _placeText = '';
  String _altitudeText = '';
  String _placeNameText = '';
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _timeText = formatNow();
    _locationText = widget.locationText;
    _placeText = widget.placeText;
    _altitudeText = widget.altitudeText;
    _placeNameText = widget.placeNameText;
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
    final controller = CameraController(_cameras[index], ResolutionPreset.high, enableAudio: false);
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
    if (mounted) setState(() { _locationText = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}'; _altitudeText = '${pos.altitude.toStringAsFixed(1)}米'; });
    final extra = await fetchPlaceAndWeather(pos.latitude, pos.longitude);
    if (mounted) setState(() { if ((extra['place'] ?? '').isNotEmpty) _placeText = extra['place']!; if ((extra['placeName'] ?? '').isNotEmpty) _placeNameText = extra['placeName']!; });
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final shot = await controller.takePicture();
      if (mounted) Navigator.pop(context, File(shot.path));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('拍照失败：$e')));
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = specFor(widget.template);
    final themeColor = spec != null ? Color(spec.themeColor) : Colors.blue;
    final lines = widget.originalStyle && widget.template != '简洁水印'
        ? buildOriginalStyleLines(timeText: _timeText, photographer: widget.photographerName, address: _placeText, altitudeText: _altitudeText, locationText: _locationText, remark: widget.remark)
        : buildWatermarkLines(
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
    final originalTitle = widget.placeTitleOverride.isNotEmpty ? widget.placeTitleOverride : (_placeNameText.isNotEmpty ? _placeNameText : (spec?.defaultTitle ?? widget.template));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('实时拍照 · ${spec?.defaultTitle ?? widget.template}'),
        backgroundColor: themeColor,
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
                // 水印条实时叠在取景底部，和成图页是同一组件、同一行顺序
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: buildWatermarkBar(
                    lines: lines,
                    themeColor: themeColor,
                    fontSize: 13,
                    opacity: 0.92,
                    simple: widget.template == '简洁水印',
                    antiFraudCode: antiFraudCode('$_timeText|$_locationText'),
                      brandImagePath: widget.brandLogoPath,
                    originalStyle: widget.originalStyle,
                    originalTitle: originalTitle,
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _cameras.length > 1 ? () { _cameraIndex = (_cameraIndex + 1) % _cameras.length; _startCamera(_cameraIndex); } : null,
                  icon: const Icon(Icons.cameraswitch, color: Colors.white),
                ),
                GestureDetector(
                  onTap: _capture,
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), color: themeColor),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
