import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/v2_login_service.dart';
import '../utils/nextcloud_api.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _prevLogin = true;
  bool _isLoggingIn = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _getPrevLogin();
  }

  Future<void> _getPrevLogin() async {
    final url = await NextcloudApi.getUrl();
    if (url != null) {
      _urlController.text = url;
      final prevLogin = await V2LoginService.prevLogin(url);
      if (prevLogin != null) {
        _completeLogin(prevLogin);
        return;
      }
    }
    setState(() => _prevLogin = false);
  }

  bool _isValidUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  Future<bool> _isNextcloudServer(String url) async {
    try {
      final response = await http.get(Uri.parse('$url/status.php')).timeout(Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['installed'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _startLogin() async {
    final rawUrl = _urlController.text.trim();
    if (!_isValidUrl(rawUrl)) {
      setState(() => _message = 'Please enter a valid URL with https://');
      return;
    }

    setState(() {
      _isLoggingIn = true;
      _message = 'Checking server...';
    });

    final isValid = await _isNextcloudServer(rawUrl);
    if (!isValid) {
      setState(() {
        _isLoggingIn = false;
        _message = 'This does not appear to be a Nextcloud server.';
      });
      return;
    }

    await NextcloudApi.saveUrl(rawUrl); // store for session
    setState(() => _message = 'Opening login window...');

    final session = await V2LoginService.login(rawUrl);
    _completeLogin(session);
  }
  void _completeLogin(Map<String, String>? session) {
    if (session != null) {
      setState(() => _message = "Login successful. Welcome ${session['username']}!");
      Navigator.pushReplacementNamed(context, '/albums');
    } else {
      setState(() {
        _isLoggingIn = false;
        _message = 'Login failed or expired.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text(_message ?? ''),
      ],
    );

    final inputWidget = Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Nextcloud Server URL',
              hintText: 'https://cloud.example.com',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _startLogin,
            child: Text('Login via Nextcloud'),
          ),
          if (_message != null) ...[
            SizedBox(height: 16),
            Text(_message!, style: TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text('Nextcloud Login')),
      body: Center(
        child: _prevLogin
            ? statusWidget
            : _isLoggingIn
                ? statusWidget
                : inputWidget,
      ),
    );
  }
}

