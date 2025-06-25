import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/nextcloud_api.dart';

class _CustomClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['User-Agent'] = 'AlbumBook';
    return _inner.send(request);
  }
}


class V2LoginService {

  static Future<Map<String, String>?> login(String baseUrl) async {
    final client = _CustomClient();
    final session = await client.post(Uri.parse('$baseUrl/index.php/login/v2'));
    if (session.statusCode != 200) return null;

    final json = jsonDecode(session.body);
    final poll = json['poll'];
    final token = poll['token'];
    final loginUrl = json['login'];
    launchUrl(Uri.parse(loginUrl));

    final start = DateTime.now();
    while (DateTime.now().difference(start).inMinutes < 20) {
      await Future.delayed(Duration(seconds: 1));
      final pollRes = await client.post(
        Uri.parse('$baseUrl/index.php/login/v2/poll'),
        body: {'token': token},
      );

      if (pollRes.statusCode == 200) {
        final auth = jsonDecode(pollRes.body);
        final appPassword = auth['appPassword'];
        final loginName = auth['loginName'];

        final prefs = await SharedPreferences.getInstance();
        prefs.setString('nc_url', baseUrl);
        prefs.setString('nc_username', loginName);
        prefs.setString('nc_password', appPassword);

        return {'username': loginName, 'password': appPassword};
      }
    }

    throw Exception('Login token expired after 20 minutes.');
  }

  static Future<Map<String, String>?> prevLogin(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('nc_url');
    final username = prefs.getString('nc_username');
    final password = prefs.getString('nc_password');

    print("prevLogin: $baseUrl $url $username $password");

    if (url == baseUrl && username != null && password != null) {
      return {'username': username, 'password': password};
    } else {
      return null;
    }
  }
}

