import 'package:flutter/material.dart';
import 'screens/nextcloud_url.dart';
import 'screens/login.dart';
import 'screens/album_list.dart';
import 'screens/album_detail.dart';
import 'screens/disclaimer.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final accepted = (prefs.getBool('licenseAccepted') ?? false);
  print('accepted: $accepted');
  runApp(AlbumBookApp(accepted: accepted));
}

class AlbumBookApp extends StatelessWidget {
  bool accepted;
  AlbumBookApp({required this.accepted});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlbumBook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: accepted ? '/home' : '/disclaimer',
      routes: {
        '/disclaimer': (context) => DisclaimerScreen(),
        '/home': (context) => NextcloudUrlScreen(),
        '/login': (context) => LoginScreen(),
        '/albums': (context) => AlbumListScreen(),
        '/album': (context) {
          final clusterId = ModalRoute.of(context)!.settings.arguments as String;
          return AlbumDetailScreen(clusterId: clusterId);
        },
      },
    );
  }
}

