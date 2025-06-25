import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DisclaimerScreen extends StatefulWidget {
  @override
  _DisclaimerScreenState createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  String _licenseText = '';
  bool _isScrolledToEnd = false;
  final ScrollController _scrollController = ScrollController();

  void _checkIfScrollable() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.position.maxScrollExtent == 0) {
        setState(() => _isScrolledToEnd = true);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('LICENSE').then((text) {
      setState(() => _licenseText = text);
      // After the text is set, check scrollability
      _checkIfScrollable();
    });

    _scrollController.addListener(() {
      if (_scrollController.offset >=
              _scrollController.position.maxScrollExtent &&
          !_scrollController.position.outOfRange) {
        if (!_isScrolledToEnd) {
          setState(() => _isScrolledToEnd = true);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('licenseAccepted', true);
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Disclaimer')),
      body: _licenseText.isEmpty
          ? Center(child: CircularProgressIndicator())
          : Center(child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.all(16.0),
                    child: Text(_licenseText),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    onPressed: _isScrolledToEnd ? _accept : null,
                    child: Text(_isScrolledToEnd ? 'Accept' : 'Scroll to the bottom to accept'),
                  ),
                ),
              ],
            )),
    );
  }
}
