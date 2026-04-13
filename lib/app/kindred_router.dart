import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/public_commons_admin.dart';
import '../core/config/app_config.dart' show isFirebaseConfigured;
import '../core/models/post_kind.dart';
import '../features/auth/profile_setup_screen.dart';
import '../features/auth/session_loading_screen.dart';
import '../features/auth/setup_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/events/create_event_screen.dart';
import '../features/events/event_detail_screen.dart';
import '../features/help_desk/compose_post_screen.dart';
import '../features/help_desk/post_detail_screen.dart';
import '../features/admin/admin_post_review_screen.dart';
import '../features/admin/admin_screen.dart';
import '../features/home/home_screen.dart';
import '../features/inbox/chat_screen.dart';
import '../features/inbox/inbox_screen.dart';
import '../features/post/post_hub_screen.dart';
import '../features/profile/connections_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/staff_screen.dart';
import 'kindred_auth_redirect.dart';
import 'kindred_profile_gate_refresh.dart';
import 'shell/app_shell.dart';
import 'shell/kindred_shell_tab_container.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter createKindredRouter({
  required KindredProfileGateRefresh profileGateRefresh,
  required KindredAuthRedirect authRedirect,
}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: profileGateRefresh,
    redirect: (context, state) {
      if (!isFirebaseConfigured) {
        return state.uri.path == '/setup' ? null : '/setup';
      }

      final user = FirebaseAuth.instance.currentUser;
      final path = state.uri.path;

      if (user == null) {
        if (path != '/sign-in' && path != '/setup') {
          authRedirect.captureFromUri(state.uri);
        }
        return path == '/sign-in' ? null : '/sign-in';
      }

      // Old app used /map, /feed, /events; bookmarks or hash routes may still point there.
      if (path == '/map' || path == '/feed' || path == '/events') {
        return '/home';
      }

      final complete = profileGateRefresh.setupComplete;

      // First Firestore snapshot not received yet — avoid flashing profile setup.
      if (complete == null) {
        if (path == '/session-loading') return null;
        return '/session-loading';
      }

      if (complete == false) {
        if (path == '/profile-setup') return null;
        return '/profile-setup';
      }

      if (path == '/profile-setup' ||
          path == '/sign-in' ||
          path == '/setup' ||
          path == '/session-loading') {
        final target = sanitizeRedirectForNavigation(authRedirect.consume()) ?? '/home';
        return target;
      }

      if (complete == true) {
        authRedirect.clearIfReached(path);
      }

      if ((path == '/admin' || path.startsWith('/admin/')) &&
          !isPublicCommonsAdminEmail(user.email)) {
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
      GoRoute(
        path: '/session-loading',
        builder: (context, state) => const SessionLoadingScreen(),
      ),
      GoRoute(
        path: '/profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: kindredShellTabContainerBuilder,
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin',
                builder: (context, state) => const AdminScreen(),
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
        path: '/posts/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ComposePostScreen(editingPostId: id);
        },
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
        path: '/admin/review/post/:postId',
        builder: (context, state) {
          final id = state.pathParameters['postId']!;
          return AdminPostReviewScreen(postId: id);
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
        path: '/connections',
        builder: (context, state) => const ConnectionsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/profile/staff',
        builder: (context, state) => const StaffScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/chat/:conversationId',
        builder: (context, state) {
          final id = state.pathParameters['conversationId']!;
          final extra = state.extra as ChatScreenRouteExtra?;
          return ChatScreen(conversationId: id, routeExtra: extra);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/new',
        redirect: (context, state) => '/post/new/event',
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/event/:id/edit',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return CreateEventScreen(editingEventId: id);
        },
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
