import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../kindred_trace.dart';

/// Uses [FirebaseApp.options.storageBucket] as an explicit `gs://` bucket so the
/// Storage SDK targets the same bucket as Firebase Console (e.g. `*.firebasestorage.app`).
FirebaseStorage createKindredFirebaseStorage() {
  final raw = Firebase.app().options.storageBucket;
  if (raw == null || raw.isEmpty) {
    kindredTrace('createKindredFirebaseStorage', 'no storageBucket, using default instance');
    return FirebaseStorage.instance;
  }
  final gs = raw.startsWith('gs://') ? raw : 'gs://$raw';
  kindredTrace('createKindredFirebaseStorage', gs);
  return FirebaseStorage.instanceFor(bucket: gs);
}
