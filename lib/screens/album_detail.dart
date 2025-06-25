import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';

import '../utils/nextcloud_api.dart';
import '../utils/smart_image.dart';
import '../widgets/directory_picker.dart';
import 'upload.dart';

class AlbumDetailScreen extends StatefulWidget {
  late final String albumName;
  late final String albumOwner;

  AlbumDetailScreen({required clusterId}) {
    final ownerAlbum = clusterId.split('/');

    this.albumOwner = ownerAlbum[0];
    this.albumName = ownerAlbum[1];
  }

  @override
  _AlbumDetailScreenState createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  late Future<(List<Map<String, dynamic>>, Map<String, String>)> _photoUrls;
  String? albumUrl = null;
  Set<int> downloaded = {};
  Set<int> downloading = {};

  void fetchPhotoUrls() {
    _photoUrls = NextcloudApi.fetchPhotosInAlbum(widget.albumName, widget.albumOwner).then((a) {
      a.forEach((d) {
        final fileId = d['fileId'];
        SmartImage.testCacheImageFull(fileId).then((cached) {
          if (cached) setState(() {
            downloaded.add(fileId);
          });
        });
      });
      return NextcloudApi.getAuthHeaders().then((b) => (a, b));
    });
  }

  @override
  void initState() {
    super.initState();
    fetchPhotoUrls();
    NextcloudApi.albumLink(widget.albumName, widget.albumOwner).then((url) {
      albumUrl = url;
    });
  }

  Future<void> _refreshPhotos() async {
    setState(() {
      fetchPhotoUrls();
    });
  }

  void _onUploadPressed() async {
    String? uploadFolder = await NextcloudApi.getUploadFolder();

    if (uploadFolder == null || uploadFolder.isEmpty || true) {
      final chosenFolder = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => DirectoryPickerScreen(),
        ),
      );

      if (chosenFolder != null && chosenFolder.trim().isNotEmpty) {
        await NextcloudApi.setUploadFolder(chosenFolder.trim());
        uploadFolder = chosenFolder.trim();
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
          withData: false, // if you want just file paths
        );

        if (result == null || result.files.isEmpty) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UploadScreen(
              filePaths: result.paths.whereType<String>().toList(),
              uploadFolder: uploadFolder!,
              albumName: widget.albumName,
              albumOwner: widget.albumOwner,
            ),
          ),
        ).then((_) { _refreshPhotos(); });
      }
    }
  }

  Future<String?> _promptForUploadFolder() async {
    String folder = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Choose Upload Folder'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(hintText: '/Photos/Uploads'),
          onChanged: (value) => folder = value,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, folder), child: Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.albumName),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_album),
            tooltip: 'Open shopping cart',
            onPressed: () {
              if (albumUrl != null)
                launchUrl(Uri.parse(albumUrl!));
            },
          ),
        ],
      ),
      body: FutureBuilder<(List<Map<String, dynamic>>, Map<String, String>)>(
        future: _photoUrls,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          final (urls, headers) = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refreshPhotos,
            child: GridView.builder(
              padding: EdgeInsets.all(16),
              itemCount: urls.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (_, i) {
                final fileId = urls[i]['fileId'];
                final isDownloaded = downloaded.contains(fileId);
                final isDownloading = downloading.contains(fileId);
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullImageScreen(
                          fileIds: urls.map((e) => e['fileId'] as int).toList(),
                          initialIndex: i,
                          headers: headers,
                          onDownload: (fileId) {
                            setState(() {
                              downloading.remove(fileId);
                              downloaded.add(fileId);
                            });
                          },
                        ),
                      ),
                    ).then((_) { _refreshPhotos(); });
                  },
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SmartImage.preview(
                          fileId: fileId,
                          params: {"x": "512", "y": "512", "etag": urls[i]['etag']},
                          headers: headers,
                          fit: BoxFit.cover,
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () {
                              if (!isDownloaded && !isDownloading) {
                                setState(() => downloading.add(fileId));
                                SmartImage.downloadAndCacheImageFull(fileId).then((f) {
                                  if (f != null) {
                                    setState(() {
                                      downloading.remove(fileId);
                                      downloaded.add(fileId);
                                    });
                                  } else {
                                    setState(() => downloading.remove(fileId));
                                  }
                                });
                              }
                            },
                            child: isDownloading
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                   valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                   strokeWidth: 2.5,
                                 ),
                               )
                             : Icon(
                                 isDownloaded ? Icons.check_circle : Icons.cloud_download,
                                 color: Colors.white,
                                 size: 24,
                               ),
                          ),
                        ),
                      ],
                    ),
                  )
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onUploadPressed,
        child: Icon(Icons.add),
      ),
    );
  }
}

class FullImageScreen extends StatefulWidget {
  final List<int> fileIds;
  final int initialIndex;
  final Map<String, String> headers;
  final void Function(int) onDownload;

  const FullImageScreen({required this.fileIds, required this.initialIndex, required this.headers, required this.onDownload});

  @override
  State<FullImageScreen> createState() => _FullImageScreenState();
}

class _FullImageScreenState extends State<FullImageScreen> {
  late PageController _controller;
  Set<int> _prefetch = {};

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void prefetch(int fileId) {
    if (!_prefetch.contains(fileId)) {
      _prefetch.add(fileId);
      SmartImage.downloadAndCacheImageFull(fileId).then((f) {
        if (f == null) {
          _prefetch.remove(fileId);
        } else {
          widget.onDownload(fileId);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(/*title: Text("Full Resolution")*/),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.fileIds.length,
        itemBuilder: (context, index) {
          final fileId = widget.fileIds[index];
          if (!_prefetch.contains(fileId)) _prefetch.add(fileId);
          final ret = Center(
            child: SmartImage.full(
              fileId: fileId,
              params: {},
              headers: widget.headers,
            ),
          );
          for (int i = 1; i < 5; i++) {
            final bufferIndexRight = index + i;
            if (-1 < bufferIndexRight && bufferIndexRight < widget.fileIds.length) {
              prefetch(widget.fileIds[bufferIndexRight]);
            }
            final bufferIndexLeft = index - i;
            if (-1 < bufferIndexLeft && bufferIndexLeft < widget.fileIds.length) {
              prefetch(widget.fileIds[bufferIndexLeft]);
            }
          }
          return ret;
        },
      ),
    );
  }
}

