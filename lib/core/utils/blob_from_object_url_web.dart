import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fetches a [web.Blob] from a `blob:` URL (e.g. [XFile.path] on web).
Future<Object?> blobFromObjectUrl(String url) async {
  try {
    final response = await web.window.fetch(url.toJS).toDart;
    if (!response.ok) return null;
    return (await response.blob().toDart) as Object;
  } on Object {
    return null;
  }
}
