import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:saver_gallery/saver_gallery.dart'; // package bạn đang dùng để lưu vào thư viện
import 'package:test_map/test_view.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Video Picker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: EasyLoading.init(),
      home: const TestView(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? _videoPath;
  VideoPlayerController? _videoController;

  // GlobalKey để lấy widget overlay (bao bọc bởi RepaintBoundary)
  final GlobalKey _overlayKey = GlobalKey();

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  // Chọn video từ thư viện

  Future<void> _pickVideo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      String? filePath = result.files.single.path;
      if (filePath != null) {
        if (_videoController != null) {
          await _videoController!.dispose();
        }
        File res = File(filePath);
        print("Đường dẫn video: ${res.lengthSync() / 1024/1024} MB");
        _videoController = VideoPlayerController.file(res);
        await _videoController!.initialize();
        _videoController!.setLooping(true);
        _videoController!.play();
        _videoController!.setVolume(0);
        setState(() {
          _videoPath = filePath;
        });
      }
    }
  }

  // Chụp lại widget overlay thành ảnh (giữ kích thước gốc)
  Future<Uint8List?> _captureOverlayWidget() async {
    try {
      RenderRepaintBoundary boundary = _overlayKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary;

      // Tăng pixelRatio để đảm bảo chất lượng cao nhất
      ui.Image image = await boundary.toImage(pixelRatio: 4.0);
      print("Kích thước ảnh overlay: ${image.width} x ${image.height}");
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      print("Lỗi khi chuyển container thành ảnh: $e");
      return null;
    }
  }

  // Xuất video với overlay giữ kích thước gốc, cách 10 pixel từ mép trái và dưới,
  // và giữ chất lượng video ban đầu (mã hóa lossless)
  Future<void> _exportVideoWithOverlay() async {
    if (_videoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chưa có video được chọn")),
      );
      return;
    }

    // Lấy kích thước video gốc
    final videoWidth = _videoController?.value.size.width ?? 1920;
    final videoHeight = _videoController?.value.size.height ?? 1080;

    String nameVideo =
        "edited_video_${DateTime.now().millisecondsSinceEpoch}";

    Uint8List? overlayImageBytes = await _captureOverlayWidget();
    if (overlayImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi khi tạo ảnh overlay")),
      );
      return;
    }

    Directory tempDir = await getTemporaryDirectory();
    String overlayImagePath = '${tempDir.path}/$nameVideo.png';
    File overlayImageFile = File(overlayImagePath);
    await overlayImageFile.writeAsBytes(overlayImageBytes);

    String outputPath = '${tempDir.path}/$nameVideo.mp4';

    // Cập nhật lệnh FFmpeg để giữ nguyên chất lượng video
    String command = '''
        -i "$_videoPath" 
        -i "$overlayImagePath" 
        -filter_complex "[0:v][1:v]overlay=10:main_h-overlay_h-10:format=auto,format=yuv444p" 
        -c:v libx265 
        -preset veryslow 
        -x265-params lossless=1 
        -c:a copy 
        -movflags +faststart 
        "$outputPath"
      '''
        .replaceAll('\n', ' ')
        .trim();

    try {
      FFmpegSession session = await FFmpegKit.execute(command);
      final ffmpegLog = await session.getOutput();
      print("FFmpeg result: $ffmpegLog");

      File outputFile = File(outputPath);

      print("Đường dẫn video xuất ra: $outputPath");
      print("Kích thước video xuất ra: ${outputFile.lengthSync() / 1024 / 1024} MB");

      if (await outputFile.exists()) {
        // Lưu video đã chỉnh sửa vào thư viện
        SaveResult? result = await SaverGallery.saveFile(
          filePath: outputPath,
          fileName: nameVideo,
          skipIfExists: true,
        );
        print("Đường dẫn video đã lưu: $result");
        if (result.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Video đã được lưu: ${result.isSuccess}")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Lỗi khi lưu video vào thư viện")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("File video không tồn tại")),
        );
      }
    } catch (e) {
      print("Lỗi khi thực thi lệnh FFmpeg: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi khi xuất video")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      // Sử dụng Stack để xếp lớp video và overlay thông tin
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: _videoController != null &&
                      _videoController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    )
                  : const Text("Chưa có video được chọn"),
            ),
            // Widget overlay (giữ kích thước gốc như bạn thiết kế)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: RepaintBoundary(
                  key: _overlayKey,
                  child: Container(
                    width: screenWidth - 20, // Trừ đi padding hai bên
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FlutterLogo(size: 50),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "Video đã chọn:",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _videoPath ?? "Chưa có video được chọn",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Độ phân giải: ${_videoController?.value.size.width.toInt() ?? 0} x ${_videoController?.value.size.height.toInt() ?? 0}",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                "Thời gian: ${_videoController?.value.duration.inSeconds ?? 0} giây",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                "Tốc độ: ${_videoController?.value.playbackSpeed ?? 1.0}x",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                "Ngày tạo: ${DateTime.now().toString()}",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Nút xuất video có overlay
            Positioned(
              top: 10,
              right: 10,
              child: ElevatedButton(
                onPressed: _exportVideoWithOverlay,
                child: const Text("Xuất video có container thông tin"),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickVideo,
        tooltip: 'Chọn video',
        child: const Icon(Icons.add),
      ),
    );
  }
}
