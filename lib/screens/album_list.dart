import 'package:flutter/material.dart';
import '../utils/nextcloud_api.dart';
import '../utils/smart_image.dart';

class AlbumListScreen extends StatefulWidget {
  @override
  _AlbumListScreenState createState() => _AlbumListScreenState();
}

class _AlbumListScreenState extends State<AlbumListScreen> {
  late Future<(List<Map<String, dynamic>>, Map<String, String>)> _albumsFuture;
  final Map<int, String> _previews = {};

  @override
  void initState() {
    super.initState();
    _albumsFuture = _loadAlbumsWithPreviews();
  }

  Future<(List<Map<String, dynamic>>, Map<String, String>)> _loadAlbumsWithPreviews() async {
    final albums = await NextcloudApi.fetchAlbums();
    final fileIds = albums
        .map((a) => a['last_added_photo'])
        .whereType<int>()
        .toSet()
        .toList();

    // Build preview URLs for each fileId
    for (final id in fileIds) {
      final url = await NextcloudApi.getPhotoPreviewUrl(id);
      if (url != null) {
        _previews[id] = url;
      }
    }
    final headers = await NextcloudApi.getAuthHeaders();

    return (albums, headers);
  }

  Future<void> _refreshAlbums() async {
    setState(() {
      _albumsFuture = _loadAlbumsWithPreviews();
    });
  }

  void _openAlbum(String clusterId) {
    Navigator.pushNamed(context, '/album', arguments: clusterId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Your Albums')),
      body: FutureBuilder<(List<Map<String, dynamic>>, Map<String, String>)>(
        future: _albumsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          final (albums, headers) = snapshot.data!;
          if (albums.isEmpty) return Center(child: Text('No albums found.'));

          return RefreshIndicator(
            onRefresh: _refreshAlbums,
            child: GridView.builder(
              padding: EdgeInsets.all(16),
              itemCount: albums.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (_, index) {
                final album = albums[index];
                final name = album['name'] ?? 'Untitled';
                final photoId = album['last_added_photo'];
                final previewUrl = _previews[photoId];
                return GestureDetector(
                  onTap: () => _openAlbum(album['cluster_id']),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey[300],
                    ),
                    clipBehavior: Clip.antiAlias, // Ensure the image respects borderRadius
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (previewUrl != null)
                          SmartImage.preview(
                            fileId: photoId,
                            params: {"x": "512", "y": "512"},
                            headers: headers,
                            fit: BoxFit.cover,
                          ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(8),
                            color: Colors.black.withOpacity(0.55),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
