import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'app/kindred_router.dart';
import 'app/kindred_scaffold_messenger.dart';
import 'core/config/app_config.dart';
import 'core/config/kindred_firebase_storage.dart';
import 'core/kindred_trace.dart';
import 'core/services/event_service.dart';
import 'core/services/messaging_service.dart';
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
    // Firestore (and other backends) with App Check *enforcement* reject clients with no token as permission-denied.
    if (kIsWeb) {
      final recaptchaSiteKey = dotenv.env['FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY']?.trim();
      final webProvider = kDebugMode
          ? WebDebugProvider()
          : (recaptchaSiteKey != null && recaptchaSiteKey.isNotEmpty
              ? ReCaptchaV3Provider(recaptchaSiteKey)
              : null);
      if (webProvider != null) {
        try {
          await FirebaseAppCheck.instance.activate(providerWeb: webProvider);
          await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
          kindredTrace(
            'main',
            kDebugMode
                ? 'App Check: WebDebugProvider — add the browser debug token (devtools / console) under Firebase Console → App Check → Manage debug tokens if enforcement is on'
                : 'App Check: ReCaptcha v3 active',
          );
        } on Object catch (e) {
          kindredTrace('main', 'FirebaseAppCheck.activate failed: $e');
        }
      } else if (!kDebugMode) {
        kindredTrace(
          'main',
          'App Check skipped (set FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY for release web if Firestore enforcement is on)',
        );
      }
    }
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
    final messagingService = MessagingService(firestore, auth);

    return MultiProvider(
      providers: [
        Provider<UserProfileService>.value(value: userProfileService),
        Provider<PostService>.value(value: postService),
        Provider<EventService>.value(value: eventService),
        Provider<MessagingService>.value(value: messagingService),
      ],
      child: _AuthProfileSync(
        child: MaterialApp.router(
          title: 'Kindred',
          theme: AppTheme.light(),
          scaffoldMessengerKey: kindredScaffoldMessengerKey,
          routerConfig: createKindredRouter(),
        ),
      ),
    );
  }
}

/// Ensures `users/{uid}` exists whenever a session is restored or the signed-in user changes,
/// not only right after the sign-in form (which could navigate away before the write finished).
class _AuthProfileSync extends StatefulWidget {
  const _AuthProfileSync({required this.child});

  final Widget child;

  @override
  State<_AuthProfileSync> createState() => _AuthProfileSyncState();
}

class _AuthProfileSyncState extends State<_AuthProfileSync> {
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attach());
  }

  void _attach() {
    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user == null) return;
      final email = user.email?.trim();
      if (email == null || email.isEmpty) return;
      final svc = context.read<UserProfileService>();
      unawaited(
        svc.ensureProfile(
          displayName: UserProfileService.preferredDisplayNameFromAuthUser(user),
        ),
      );
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
