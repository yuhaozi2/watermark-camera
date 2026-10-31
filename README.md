# 水印相机 Flutter 版（干净重写）

这是一个 Flutter 源码项目，不是现成的 APK/IPA。

## 功能
- 拍照 / 从相册导入
- 自动水印：时间、日期、星期
- 地点：手填或一键定位
- 模板：时间地点、打卡考勤、工作记录、会议、监理巡检、工程项目、物业、销售、电力、团队品牌、简洁水印、对比拼图、工作汇报拼图、日常拼图
- 水印位置可调，生成后通过分享面板保存到相册
- 拼图、视频水印按模板思路实现，不含原厂图片和特效

## 怎么运行和打包
1. 安装 Flutter SDK（官网 flutter.dev），并装 Android Studio / Xcode
2. 在项目目录运行：
   ```
   flutter pub get
   flutter run
   ```
3. 打包安卓 APK：
   ```
   flutter build apk --release
   ```
   生成的 APK 在 build/app/outputs/flutter-apk/app-release.apk
4. 打包苹果 IPA 需要在 Mac 上，并有苹果开发者账号和证书：
   ```
   flutter build ipa --release
   ```

## 为什么不直接给 APK
- 我的环境里没有 Flutter SDK、Android SDK，苹果打包还需要 Mac 和苹果开发者账号，没法替你签一个能直接装的正式包。
- 给你源码 + 上面步骤，是最稳的办法，装好 Flutter 后一般几分钟就能出包。

## 注意
- 首次打开请允许摄像头、相册、定位权限。
- 本项目为干净重写，不含原厂图片、账号、VIP、团队同步和云端功能。
