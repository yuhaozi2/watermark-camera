import 'package:flutter/material.dart';
import 'pages/watermark_camera_page.dart';
void main() => runApp(const WatermarkApp());
class WatermarkApp extends StatelessWidget {
  const WatermarkApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '水印相机',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const WatermarkCameraPage(),
    );
  }
}
