import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path/path.dart' as p;
import '../utils/nextcloud_api.dart';
import 'dart:io';

class UploadScreen extends StatefulWidget {
  final String albumName;
  final String albumOwner;
  final List<String> filePaths;
  final String uploadFolder;

  UploadScreen({
    required this.filePaths,
    required this.uploadFolder,
    required this.albumName,
    required this.albumOwner
  });

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  int current = 0;
  List<bool> completed = [];
  List<double> progress = [];
  bool get _allUploadsComplete => completed.every((c) => c);

  @override
  void initState() {
    super.initState();
    completed = List.generate(widget.filePaths.length, (_) => false);
    progress = List.generate(widget.filePaths.length, (_) => 0);
    WakelockPlus.enable(); // prevent sleep
    _startUpload();
  }

  @override
  void dispose() {
    WakelockPlus.disable(); // release wakelock
    super.dispose();
  }

  Future<void> _startUpload() async {
    for (int i = 0; i < widget.filePaths.length; i++) {
      final path = widget.filePaths[i];
      final result = await NextcloudApi.uploadFileWithProgress(
        widget.albumName,
        widget.albumOwner,
        path,
        widget.uploadFolder,
        onProgress: (pct) {
          setState(() => progress[i] = pct);
        },
      );
      setState(() {
        completed[i] = result;
        current = i + 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.filePaths.length;
    return Scaffold(
      // appBar: AppBar(title: Text('Uploading $total image${total == 1 ? '' : 's'}')),
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _allUploadsComplete ? Icons.check : Icons.close,
          ),
          onPressed: () {
            if (_allUploadsComplete) {
              Navigator.pop(context); // ✅ Finished — go back
            } else {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Cancel Uploads?'),
                  content: Text('Uploads are still in progress. Are you sure you want to exit?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: Text('No')),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx); // close dialog
                        Navigator.pop(context); // leave screen
                      },
                      child: Text('Yes'),
                    ),
                  ],
                ),
              );
            }
          },
        ),
        title: Text('Uploading $total image${total == 1 ? '' : 's'}'),
      ),
      body: ListView.builder(
        itemCount: widget.filePaths.length,
        itemBuilder: (_, index) {
          final name = p.basename(widget.filePaths[index]);
          return ListTile(
            title: Text(name),
            subtitle: LinearProgressIndicator(
              value: completed[index] ? 1 : progress[index],
            ),
            trailing: completed[index]
                ? Icon(Icons.check_circle, color: Colors.green)
                : Icon(Icons.cloud_upload, color: Colors.grey),
          );
        },
      ),
    );
  }
}

