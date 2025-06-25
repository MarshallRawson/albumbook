import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../utils/nextcloud_api.dart';

class NextcloudUrlScreen extends StatefulWidget {
  @override
  _NextcloudUrlScreenState createState() => _NextcloudUrlScreenState();
}

class _NextcloudUrlScreenState extends State<NextcloudUrlScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    NextcloudApi.getUrl().then((url) {
      if (url != null) {
        Navigator.pushReplacementNamed(context, '/login'); // Skip input
      }
    });
  }

  void _saveAndContinue() async {
    String url = _controller.text.trim();
    if (!url.startsWith("http")) url = "https://$url";
    if (!url.endsWith("/")) url = "$url/";
    await NextcloudApi.saveUrl(url);
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Enter Nextcloud URL')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(labelText: 'https://yourcloud.com'),
              onSubmitted: (_) => _saveAndContinue(),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveAndContinue,
              child: Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

