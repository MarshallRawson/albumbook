import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'dart:typed_data';

import 'dart:convert';
import 'dart:io';
import 'dart:async';

class NextcloudApi {
  static const _keyUrl = 'nextcloud_url';

  static Future<void> saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUrl, url);
  }

  static Future<String?> getUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyUrl);
    return url;
  }

  static Future<Map<String, String>> getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('nc_username');
    final password = prefs.getString('nc_password');

    return {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      'OCS-APIREQUEST': 'true',
    };
  }

  static Future<bool> authenticate(String username, String password) async {
    final url = await getUrl();
    if (url == null) return false;

    final uri = Uri.parse('$url/ocs/v2.php/cloud/capabilities?format=json');

    final response = await http.get(uri, headers: await getAuthHeaders());

    return response.statusCode == 200;
  }

  static Future<String> albumLink(String albumName, String albumOwner) async {
    final url = await getUrl();
    return '${url}apps/memories/albums/$albumOwner/$albumName';
  }

  static Future<List<Map<String, dynamic>>> fetchAlbums() async {
    final url = await getUrl();
    final prefs = await SharedPreferences.getInstance();

    final username = prefs.getString('nc_username');
    final password = prefs.getString('nc_password');

    if (url == null || username == null || password == null) return [];

    var headers = await getAuthHeaders();
    headers['Accept'] = 'application/json';
    final response = await http.get(
      Uri.parse('${url}apps/memories/api/clusters/albums'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      print("response code ${response.statusCode}");
      return [];
    }
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((i) => i as Map<String, dynamic>).toList();
  }

  static Future<String?> getPhotoPreviewUrl(int fileId) async {
    final url = await getUrl();
    if (url == null) return null;
    return '${url}apps/photos/api/v1/preview/$fileId';
  }

  static Future<List<Map<String, dynamic>>> fetchPhotosInAlbum(
    String albumName,
    String albumOwner
  ) async {
    final url = await getUrl();
    final prefs = await SharedPreferences.getInstance();

    final username = prefs.getString('nc_username');
    final headers = await getAuthHeaders();

    if (url == null || headers == null || username == null) return [];

    final davUrl = albumOwner == username
      ? Uri.parse('${url}remote.php/dav/photos/$username/albums/$albumName/')
      : Uri.parse('${url}remote.php/dav/photos/$username/sharedalbums/$albumName ($albumOwner)/')
    ;

    final xmlBody = '''<?xml version="1.0"?>
      <d:propfind xmlns:d="DAV:"
        xmlns:oc="http://owncloud.org/ns"
        xmlns:nc="http://nextcloud.org/ns"
        xmlns:ocs="http://open-collaboration-services.org/ns">
        <d:prop>
          <d:getcontentlength />
          <d:getcontenttype />
          <d:getetag />
          <d:getlastmodified />
          <d:resourcetype />
          <nc:metadata-photos-size />
          <nc:metadata-photos-original_date_time />
          <nc:metadata-files-live-photo />
          <nc:has-preview />
          <nc:hidden />
          <oc:favorite />
          <oc:fileid />
          <oc:permissions />
        </d:prop>
      </d:propfind>
  ''';

    final request = await http.Request('PROPFIND', davUrl)
      ..headers.addAll({
        ...headers,
        'Depth': '1',
        'Content-Type': 'text/plain;charset=UTF-8',
        'Accept': 'text/plain',
      })
      ..body = xmlBody;

    final client = http.Client();
    final streamed = await client.send(request);
    final xmlString = await streamed.stream.bytesToString();
    client.close();

    final document = XmlDocument.parse(xmlString);
    final List<Map<String, dynamic>> previews = [];

    for (final responseNode in document.findAllElements('d:response')) {
      final props = responseNode.getElement('d:propstat')?.getElement('d:prop');
      if (props == null) continue;

      final fileIdStr = props.getElement('oc:fileid')?.innerText;
      final etag = props.getElement('d:getetag')?.innerText;
      final mime = props.getElement('d:getcontenttype')?.innerText ?? '';

      if (fileIdStr == null || etag == null || !mime.startsWith('image/')) continue;

      final fileId = int.tryParse(fileIdStr);
      if (fileId == null) continue;

      previews.add({
        'fileId': fileId,
        'etag': etag,
        'mime': mime,
      });
    }
    return previews;
  }

  static Future<String?> getUploadFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('upload_folder');
  }

  static Future<void> setUploadFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('upload_folder', path);
  }

  static Future<bool> uploadFileWithProgress(
    String albumName,
    String albumOwner,
    String localPath,
    String remotePath, {
    required void Function(double) onProgress,
  }) async {
    final url = await getUrl();
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('nc_username');
    final headers = await getAuthHeaders();

    if (url == null || headers == null || username == null) return false;

    final file = File(localPath);
    if (!file.existsSync()) return false;

    final filename = p.basename(localPath);
    final encodedPath = Uri.encodeFull('$remotePath/$filename');
    final uploadUrl = Uri.parse('$url/remote.php/dav/files/$username/$encodedPath');

    final total = await file.length();
    int bytesSent = 0;

    final stream = file.openRead().transform(
      StreamTransformer.fromHandlers(
        handleData: (chunk, sink) {
          bytesSent += chunk.length;
          onProgress(bytesSent / total);
          sink.add(chunk);
        },
      ),
    );
    final streamedRequest = http.StreamedRequest('PUT', uploadUrl);
    streamedRequest.headers.addAll(headers);

    stream.listen(
      (Object? x) {
        final chunk = x! as List<int>;
        bytesSent += chunk.length;
        onProgress(bytesSent / total);
        streamedRequest.sink.add(chunk); // now safe
      },
      onDone: () => streamedRequest.sink.close(),
      onError: (_) => streamedRequest.sink.close(),
    );

    final response = await http.Client().send(streamedRequest);
    await response.stream.drain();
    if (!(response.statusCode == 201 || response.statusCode == 204)) {
      return false;
    }

    final dest = albumOwner == username
      ? Uri.parse('${url}remote.php/dav/photos/$username/albums/$albumName/')
      : Uri.parse('${url}remote.php/dav/photos/$username/sharedalbums/$albumName ($albumOwner)/')
    ;
    final copyRequest = await http.Request('COPY', uploadUrl)..headers.addAll({
      ...headers,
      'Accept': 'application/json',
      'Destination': '$dest$filename',
    });
    final client = http.Client();
    final copyResponse = await client.send(copyRequest);
    final body = await copyResponse.stream.bytesToString();
    client.close();
    return copyResponse.statusCode == 201;
  }

  static Future<List<String>> fetchRemoteDirectories({String path = '/'}) async {
    final url = await getUrl();
    final headers = await getAuthHeaders();
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('nc_username');
    if (url == null || headers == null || username == null) return [];

    final davUrl = Uri.parse('$url/remote.php/dav/files/$username$path');

    final body = '''<?xml version="1.0"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:resourcetype/>
      </d:prop>
    </d:propfind>''';

    final response = await http.Request('PROPFIND', davUrl)
      ..headers.addAll({
        ...headers,
        'Depth': '1',
        'Content-Type': 'text/xml',
      })
      ..body = body;

    final client = http.Client();
    final streamed = await client.send(response);
    final xml = await streamed.stream.bytesToString();
    client.close();

    final doc = XmlDocument.parse(xml);
    final hrefs = <String>[];

    for (final resp in doc.findAllElements('d:response')) {
      final href = resp.getElement('d:href')?.innerText;
      final isCollection = resp
          .findAllElements('d:collection')
          .isNotEmpty;

      if (href != null && isCollection) {
        final relative = Uri.decodeFull(href)
            .replaceFirst('/remote.php/dav/files/$username', '');
        if (relative != path) hrefs.add(relative);
      }
    }
    return hrefs;
  }

  static Future<String> downloadUrl(int fileId) async {
    final url = await getUrl();
    return '${url}apps/memories/api/stream/$fileId';
  }

  static Future<Uint8List?> downloadFileContents(int fileId) async {
    final url = await getUrl();
    final headers = await getAuthHeaders();

    if (url == null || headers == null) return null;

    final response = await http.get(
      Uri.parse(await downloadUrl(fileId)),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return response.bodyBytes; // ✅ Raw file content
    } else {
      print('Failed to download file $fileId: ${response.statusCode}');
      return null;
    }
  }
}
