import 'blob_from_object_url_stub.dart'
    if (dart.library.html) 'blob_from_object_url_web.dart' as impl;

/// Web: returns a JS [Blob] for [Reference.putBlob]. Other platforms: null.
Future<Object?> blobFromObjectUrl(String url) => impl.blobFromObjectUrl(url);
