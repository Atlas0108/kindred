import '../../firebase_options.dart';

bool get isFirebaseConfigured {
  final opts = DefaultFirebaseOptions.web;
  final id = opts.projectId;
  final key = opts.apiKey;
  if (id.isEmpty || id.startsWith('REPLACE')) return false;
  if (key.contains('PASTE_') || key.startsWith('REPLACE')) return false;
  return true;
}
