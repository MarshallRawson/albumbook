import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'nextcloud_api.dart';

class SmartImage extends StatelessWidget {
  final int fileId;
  final Map<String, String> params;
  final Map<String, String> headers;
  final BoxFit fit;
  final bool preview;

  const SmartImage._({
    Key? key,
    required this.fileId,
    required this.params,
    required this.headers,
    required this.preview,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  SmartImage.preview({
    Key? key,
    required int fileId,
    required Map<String, String> params,
    required Map<String, String> headers,
    BoxFit fit = BoxFit.cover,
  }) : this._(
    key: key,
    fileId: fileId,
    params: params,
    headers: headers,
    fit: fit,
    preview: true,
  );

  SmartImage.full({
    Key? key,
    required int fileId,
    required Map<String, String> params,
    required Map<String, String> headers,
    BoxFit fit = BoxFit.cover,
  }) : this._(
    key: key,
    fileId: fileId,
    params: params,
    headers: headers,
    fit: fit,
    preview: false,
  );

  bool _isHeic(Uint8List bytes) {
    final header = String.fromCharCodes(bytes.take(12));
    return header.contains('ftypheic') || header.contains('ftyphevc');
  }

  static Future<File> _getCachedFile(String filename) async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${dir.path}/image_cache');
    if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
    return File('${cacheDir.path}/$filename');
  }

  Future<File> _downloadAndCacheImagePreview() async {
    final urlParams = params.entries.map((e) => "${e.key}=${e.value}").toList().join("&");
    final previewUrl = "${await NextcloudApi.getPhotoPreviewUrl(fileId)}?$urlParams";
    final filename = md5.convert(utf8.encode(previewUrl)).toString();
    final file = await _getCachedFile(filename);
    if (await file.exists()) return file;
    final response = await http.get(Uri.parse(previewUrl), headers: headers);
    if (response.statusCode == 200) {
      final incomingBytes = response.bodyBytes.length;
      await _enforceCacheLimit(file.parent, incomingBytes);
      await file.writeAsBytes(response.bodyBytes);
    } else {
      final bytes = await NextcloudApi.downloadFileContents(fileId);
      if (bytes != null) {
        await _enforceCacheLimit(file.parent, bytes.length);
        await file.writeAsBytes(bytes);
      }
    }
    return file;
  }

  Future<ImageProvider> _loadImagePreview() async {
    final file = await _downloadAndCacheImagePreview();
    final bytes = await file.readAsBytes();
    if (_isHeic(bytes)) {
      final compressed = await FlutterImageCompress.compressWithFile(
        file.path,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) {
        throw Exception("Failed to convert HEIC image");
      }
      await file.writeAsBytes(compressed);
    }
    return FileImage(file);
  }

  Future<File> _downloadAndCacheImageFull() async {
    final ret = await downloadAndCacheImageFull(fileId);
    if (ret == null)
      throw Exception("Failed to download Image");
    return ret;
  }

  static Future<bool> testCacheImageFull(int fileId) async {
    final downloadUrl = await NextcloudApi.downloadUrl(fileId);
    final filename = md5.convert(utf8.encode(downloadUrl)).toString();
    final file = await _getCachedFile(filename);
    if (await file.exists() && await file.length() > 0) {
      return true;
    }
    return false;
  }

  static Future<File?> downloadAndCacheImageFull(int fileId) async {
    final downloadUrl = await NextcloudApi.downloadUrl(fileId);
    final filename = md5.convert(utf8.encode(downloadUrl)).toString();
    final file = await _getCachedFile(filename);
    if (await file.exists() && await file.length() > 0) {
      return file;
    }
    final raf = await file.open(mode: FileMode.write);
    final bytes = await NextcloudApi.downloadFileContents(fileId);
    if (bytes != null && bytes.length > 0) {
      await _enforceCacheLimit(file.parent, bytes.length);
      await raf.writeFrom(bytes);
    } else {
      if (await file.exists()) await file.delete();
      raf.close();
      return null;
    }
    raf.close();
    return file;
  }

  Future<ImageProvider> _loadImageFull() async {
    final file = await _downloadAndCacheImageFull();
    final bytes = await file.readAsBytes();
    if (_isHeic(bytes)) {
      final compressed = await FlutterImageCompress.compressWithFile(
        file.path,
        format: CompressFormat.jpeg,
      );
      if (compressed == null) {
        throw Exception("Failed to convert HEIC image");
      }
      await file.writeAsBytes(compressed);
    }
    return FileImage(file);
  }

  static Future<void> _enforceCacheLimit(Directory cacheDir, int incomingBytes, {int maxBytes = 5 * 1024 * 1024 * 1024}) async {
    final files = await cacheDir.list().where((f) => f is File).cast<File>().toList();

    // Get sizes and sort by last accessed
    final fileStats = await Future.wait(files.map((f) async {
      final stat = await f.stat();
      return {
        'file': f,
        'size': stat.size as int,
        'accessed': stat.accessed ?? stat.changed,
      };
    }));

    int totalSize = fileStats.fold(0, (sum, f) => sum + (f['size'] as int));

    if (totalSize + incomingBytes <= maxBytes) return;

    // Sort by least recently accessed
    fileStats.sort((a, b) =>
        (a['accessed'] as DateTime).compareTo(b['accessed'] as DateTime));

    for (var f in fileStats) {
      final file = f['file'] as File;
      final size = f['size'] as int;
      await file.delete();
      totalSize -= size;
      if (totalSize + incomingBytes <= maxBytes) break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return preview
      ? FutureBuilder<ImageProvider>(
        future: _loadImagePreview(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
            return Image(image: snapshot.data!, fit: fit);
          } else if (snapshot.hasError) {
            return const Icon(Icons.broken_image);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      )
    : FutureBuilder<ImageProvider>(
      future: _loadImageFull(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
          return Image(image: snapshot.data!);
        } else if (snapshot.hasError) {
          return const Icon(Icons.broken_image);
        } else {
          return const Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}

