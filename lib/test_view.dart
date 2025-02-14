import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/ffprobe_kit.dart';

import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:video_player/video_player.dart';
import 'package:widgets_to_image/widgets_to_image.dart';

class TestView extends StatefulWidget {
  const TestView({super.key});

  @override
  State<TestView> createState() => _TestViewState();
}

class _TestViewState extends State<TestView> {
  String? _videoPath;
  VideoPlayerController? _videoController;
  final WidgetsToImageController _widgetsToImageController = WidgetsToImageController();
  Uint8List? bytes;

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    _videoController?.dispose();
  }

  void _exportVideo() async {
    if(_videoPath == null) {
      print("Chưa có video được chọn");
      return;
    }

    if(bytes == null) {
      print("Chưa có ảnh overlay");
      return;
    }

    // Lấy thời lượng video để tính phần trăm
    final duration = await FFprobeKit.getMediaInformation(_videoPath!).then(
            (info) => info.getMediaInformation()?.getDuration() ?? "0"
    );
    final totalDuration = double.parse(duration);

    EasyLoading.show(status: "Đang xử lý: 0%");

    double widthVideo = _videoController!.value.size.width - 20;
    String nameVideo = "edited_video_${DateTime.now().millisecondsSinceEpoch}";
    String nameImage = "overlay_${DateTime.now().millisecondsSinceEpoch}";

    Directory appDocDir;
    try {
      appDocDir = await getTemporaryDirectory();
    } catch(e) {
      print("Error get app doc dir: $e");
      return;
    }

    String overlayPath = "${appDocDir.path}/$nameImage.png";
    File overlayImageFile = File(overlayPath);

    try {
      await overlayImageFile.writeAsBytes(bytes!);
    } catch(e) {
      print("Error write overlay image file: $e");
      return;
    }

    String outputPath = "${appDocDir.path}/$nameVideo.mp4";
    String command = '-i $_videoPath -i $overlayPath -filter_complex "[1]scale=$widthVideo:-1[img];[0][img]overlay=10:H-h-10" -c:v h264 -b:v 8M -maxrate 10M -bufsize 5M -movflags +faststart -threads 4 -c:a copy -y $outputPath';

    try {
      // Sử dụng executeAsync thay vì execute
      await FFmpegKit.executeAsync(
          command,
              (session) async {
            final returnCode = await session.getReturnCode();

            if (ReturnCode.isSuccess(returnCode)) {
              File outputFile = File(outputPath);
              print("Kích thước video xuất ra: ${outputFile.lengthSync() / 1024 / 1024} MB");

              if (await outputFile.exists()) {
                SaveResult? result = await SaverGallery.saveFile(
                  filePath: outputPath,
                  fileName: nameVideo,
                  skipIfExists: true,
                );

                if (result.isSuccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Video đã được lưu thành công")),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Lỗi khi lưu video vào thư viện")),
                  );
                }
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Lỗi khi xử lý video")),
              );
            }
            EasyLoading.dismiss();
          },
          null, // Log callback
              (statistics) {
            // Tính phần trăm tiến độ
            if (totalDuration > 0) {
              final timeInMillis = statistics.getTime();
              if (timeInMillis > 0) {
                final progress = (timeInMillis / (totalDuration * 1000)) * 100;
                EasyLoading.showProgress(
                    progress / 100,
                    status: "Đang xử lý: ${progress.toStringAsFixed(0)}%"
                );
              }
            }
          }
      );

    } catch(e) {
      print("Error: $e");
      EasyLoading.dismiss();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Lỗi: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
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

          Positioned(
            top: 10,
            left: 10,
            child: SafeArea(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      final bytes = await _widgetsToImageController.capture(pixelRatio: 10);
                      setState(() {
                        this.bytes = bytes;
                      });
                    },
                    child: const Text("convert widget imagge"),
                  ),

                  ElevatedButton(
                    onPressed: _exportVideo,
                    child: const Text("export video"),
                  ),
                ],
              ),
            ),
          ),



          if(bytes != null)
            Positioned(
              top: 200,
              left: 10,
              right: 10,
              child: Image.memory(bytes!, width: MediaQuery.of(context).size.width),
            ),

          Positioned(
            bottom: 20,
            left: 10,
            right: 10,
            child: WidgetsToImage(
              controller: _widgetsToImageController,
              child: Container(
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
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
        },
        child: const Icon(Icons.video_library),
      ),
    );
  }
}
