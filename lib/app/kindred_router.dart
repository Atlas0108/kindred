import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/config/app_config.dart' show isFirebaseConfigured;
import '../core/models/post_kind.dart';
import '../features/auth/setup_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/events/create_event_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/help_desk/compose_post_screen.dart';
import '../features/help_desk/post_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/inbox/inbox_screen.dart';
import '../features/post/post_hub_screen.dart';
import '../features/profile/profile_screen.dart';
import 'go_router_refresh.dart';
import 'shell/app_shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter createKindredRouter() {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: isFirebaseConfigured
        ? GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges())
        : null,
    redirect: (context, state) {
      if (!isFirebaseConfigured) {
        return state.uri.path == '/setup' ? null : '/setup';
      }

      final user = FirebaseAuth.instance.currentUser;
      final path = state.uri.path;

      if (user == null) {
        return path == '/sign-in' ? null : '/sign-in';
      }

      // Old app used /map, /feed, /events; bookmarks or hash routes may still point there.
      if (path == '/map' || path == '/feed' || path == '/events') {
        return '/home';
      }

      if (path == '/sign-in' || path == '/setup') {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => '/home',
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/post',
                builder: (context, state) => const PostHubScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                builder: (context, state) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/compose',
        builder: (context, state) {
          final kind = state.uri.queryParameters['kind'];
          PostKind? initial;
          if (kind == 'offer') initial = PostKind.helpOffer;
          if (kind == 'request') initial = PostKind.helpRequest;
          return ComposePostScreen(initialDeskKind: initial);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/post/new/event',
        builder: (context, state) => const CreateEventScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/posts/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return PostDetailScreen(postId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/u/:userId',
        builder: (context, state) {
          final uid = state.pathParameters['userId']!;
          return ProfileScreen(userId: uid);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/new',
        redirect: (context, state) => '/post/new/event',
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return EventDetailScreen(eventId: id);
        },
      ),
    ],
  );
}
