import 'package:flutter/material.dart';
import '../utils/nextcloud_api.dart';

class DirectoryPickerScreen extends StatefulWidget {
  final String initialPath;

  DirectoryPickerScreen({this.initialPath = '/'});

  @override
  _DirectoryPickerScreenState createState() => _DirectoryPickerScreenState();
}

class _DirectoryPickerScreenState extends State<DirectoryPickerScreen> {
  String currentPath = '/';
  List<String>? directories = null;

  @override
  void initState() {
    super.initState();
    currentPath = widget.initialPath;
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    final dirs = await NextcloudApi.fetchRemoteDirectories(path: currentPath);
    setState(() {
      if (dirs.length > 0)
        directories = dirs;
      else
        directories = null;
    });
  }

  void _enterDirectory(String subdir) {
    setState(() {
      currentPath = subdir.endsWith('/') ? subdir : '$subdir/';
      directories = [];
    });
    _loadDirectories();
  }

  @override
  Widget build(BuildContext context) {
    final pathSegments = currentPath
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Choose Upload Folder'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, currentPath),
            child: Text('Use This', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (pathSegments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Wrap(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        currentPath = '/';
                      });
                      _loadDirectories();
                    },
                    child: Text('Home'),
                  ),
                  for (int i = 0; i < pathSegments.length; i++) ...[
                    Text(' / '),
                    TextButton(
                      onPressed: () {
                        final partial = '/' +
                            pathSegments.sublist(0, i + 1).join('/') +
                            '/';
                        setState(() => currentPath = partial);
                        _loadDirectories();
                      },
                      child: Text(pathSegments[i]),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: directories == null
                ? Center(child: Text("No Child Directories"))
                : directories!.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: directories!.length,
                      itemBuilder: (_, i) {
                        final dir = directories![i];
                        final label = dir.replaceFirst(currentPath, '');
                        return ListTile(
                          leading: Icon(Icons.folder),
                          title: Text(label),
                          onTap: () => _enterDirectory(dir),
                        );
                      },
                    ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          icon: Icon(Icons.check),
          label: Text('Use This Folder'),
          onPressed: () {
            Navigator.pop(context, currentPath);
          },
          style: ElevatedButton.styleFrom(
            minimumSize: Size.fromHeight(48),
          ),
        ),
      ),
    );
  }
}

