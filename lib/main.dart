import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app/kindred_router.dart';
import 'app/kindred_scaffold_messenger.dart';
import 'core/config/app_config.dart';
import 'core/config/kindred_firebase_storage.dart';
import 'core/kindred_trace.dart';
import 'core/services/event_service.dart';
import 'core/services/post_service.dart';
import 'core/services/user_profile_service.dart';
import 'features/auth/setup_screen.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  kindredTrace('main', 'WidgetsFlutterBinding done');
  await dotenv.load(fileName: '.env', isOptional: true);
  kindredTrace('main', 'dotenv loaded');
  if (isFirebaseConfigured) {
    kindredTrace('main', 'Firebase.initializeApp start');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    kindredTrace('main', 'Firebase.initializeApp done');
    // Web: IndexedDB persistence lets reads resolve from cache when offline.
    // Prefer auto long-polling detection; forcing long polling can leave some `set()` Futures
    // pending forever on web while the write still reaches the server (spinner never clears).
    FirebaseFirestore.instance.settings = Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      webExperimentalForceLongPolling: null,
      webExperimentalAutoDetectLongPolling: kIsWeb ? true : null,
      webPersistentTabManager: kIsWeb ? const WebPersistentMultipleTabManager() : null,
    );
    kindredTrace('main', 'Firestore.settings applied kIsWeb=$kIsWeb');
  } else {
    kindredTrace('main', 'Firebase not configured (setup screen)');
  }
  kindredTrace('main', 'runApp');
  runApp(const KindredApp());
}

class KindredApp extends StatelessWidget {
  const KindredApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isFirebaseConfigured) {
      return MaterialApp(
        title: 'Kindred',
        theme: AppTheme.light(),
        home: const SetupScreen(),
      );
    }

    final firestore = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final storage = createKindredFirebaseStorage();
    final userProfileService = UserProfileService(firestore, auth, storage);
    final postService = PostService(firestore, auth, storage);
    final eventService = EventService(firestore, auth, storage);

    return MultiProvider(
      providers: [
        Provider<UserProfileService>.value(value: userProfileService),
        Provider<PostService>.value(value: postService),
        Provider<EventService>.value(value: eventService),
      ],
      child: MaterialApp.router(
        title: 'Kindred',
        theme: AppTheme.light(),
        scaffoldMessengerKey: kindredScaffoldMessengerKey,
        routerConfig: createKindredRouter(),
      ),
    );
  }
}
