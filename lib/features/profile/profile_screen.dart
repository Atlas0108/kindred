import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/view_as_controller.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/models/user_account_type.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/post_service.dart';
import '../../core/services/connection_service.dart';
import '../../core/services/messaging_service.dart';
import '../../core/services/user_profile_service.dart';
import '../inbox/chat_screen.dart';
import 'profile_connection_button.dart';
import 'set_home_area_sheet.dart';
import '../../core/utils/blob_from_object_url.dart';
// import '../../widgets/didit_verification_sheet.dart';
import '../../widgets/pending_connection_requests_badge.dart';
import '../../widgets/post_kind_icon_badge.dart';
import '../../widgets/view_as_identity_menu.dart';

/// Matches the Kindred home cream canvas.
const _pageBackground = Color(0xFFF9F7F2);

const _headerGreen = Color(0xFF2E7D5A);
const _editFabGreen = Color(0xFF1F5C40);
const _slateSubtitle = Color(0xFF5B6B7A);
const _statBlue = Color(0xFF3D5A80);
// /// Verified badge on own profile (below location row).
// const _verifiedBlue = Color(0xFF2563EB);
const _gearBg = Color(0xFFECECEA);
const _gearIcon = Color(0xFF5C5C5C);
const _profileGearSize = 38.0;
const _profileGearIconSize = 16.0;

/// Home-area control in edit profile: show saved city/region label when set.
String _homeAreaEditButtonLabel(UserProfile p) {
  final city = p.homeCityLabel?.trim();
  if (p.homeGeoPoint == null) {
    return 'Set home for local feed';
  }
  if (city != null && city.isNotEmpty) {
    return city;
  }
  return 'Home area — tap to update';
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.userId});

  /// When null, shows the signed-in user (e.g. Profile tab). When set, shows that member (e.g. from `/u/:userId`).
  final String? userId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _selfEnsureRequested = false;

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _selfEnsureRequested = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view your profile.')));
    }

    final viewAs = context.watch<ViewAsController>();
    final targetUid = widget.userId ?? viewAs.effectiveProfileUid;
    final svc = context.read<UserProfileService>();
    final fromShell = widget.userId == null;
    final fromProfileTab = fromShell;
    final actingAsOrganization = viewAs.isActingAsOrganization;

    Widget body = ColoredBox(
      color: _pageBackground,
      child: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: svc.profileStream(targetUid),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final p = snap.data;
            if (p == null) {
              final loadingOwnAuthProfile = targetUid == user.uid;
              if (loadingOwnAuthProfile) {
                final email = user.email?.trim();
                if (email == null || email.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add an email address to your account to show your profile.',
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: _slateSubtitle),
                      ),
                    ),
                  );
                }
                if (!_selfEnsureRequested) {
                  _selfEnsureRequested = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    unawaited(svc.ensureProfile(displayName: 'Neighbor'));
                  });
                }
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading your profile…'),
                    ],
                  ),
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'This neighbor’s profile is not available yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _slateSubtitle),
                  ),
                ),
              );
            }
            final isAuthUserDoc = user.uid == p.uid;
            return _ProfileBody(
              key: ValueKey(p.uid),
              profile: p,
              isAuthUserDoc: isAuthUserDoc,
              fromProfileTab: fromProfileTab,
              actingAsOrganization: actingAsOrganization,
            );
          },
        ),
      ),
    );

    if (fromShell) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: body,
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({
    super.key,
    required this.profile,
    required this.isAuthUserDoc,
    required this.fromProfileTab,
    required this.actingAsOrganization,
  });

  final UserProfile profile;
  final bool isAuthUserDoc;
  final bool fromProfileTab;
  final bool actingAsOrganization;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  bool _uploadingPhoto = false;

  UserProfile get profile => widget.profile;

  void _openEdit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProfileEditSheet(profile: profile),
    );
  }

  Future<void> _pickAndUploadProfilePhoto() async {
    if (_uploadingPhoto) return;
    final profileService = context.read<UserProfileService>();
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;

    Uint8List? bytes;
    Object? webBlob;
    final mime = x.mimeType;

    if (kIsWeb) {
      webBlob = await blobFromObjectUrl(x.path);
      if (webBlob == null) {
        bytes = await x.readAsBytes();
      }
    } else {
      bytes = await x.readAsBytes();
    }

    if (!mounted) return;
    setState(() => _uploadingPhoto = true);
    try {
      await profileService.uploadAndSetProfilePhoto(
        imageBytes: bytes,
        webImageBlob: webBlob,
        imageContentType: mime,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update photo: $e')));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Widget _buildPrimaryProfileActions(BuildContext context, ThemeData theme) {
    if (widget.isAuthUserDoc && !widget.actingAsOrganization) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: FilledButton(
              onPressed: () => context.go('/inbox'),
              style: FilledButton.styleFrom(
                backgroundColor: _headerGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Inbox'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: _profileGearSize,
            height: _profileGearSize,
            child: Material(
              color: _gearBg,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openEdit(context),
                child: const Center(
                  child: Icon(
                    Icons.settings,
                    color: _gearIcon,
                    size: _profileGearIconSize,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    if (widget.fromProfileTab && widget.actingAsOrganization) {
      return const SizedBox.shrink();
    }
    return FilledButton(
      onPressed: () => _openChat(context),
      style: FilledButton.styleFrom(
        backgroundColor: _headerGreen,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: const Text('Message'),
    );
  }

  void _openChat(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final myUid = context.read<ViewAsController>().effectiveProfileUid;
    if (myUid.isEmpty) return;
    final id = MessagingService.conversationIdForPair(myUid, profile.uid);
    final otherName = UserProfile.displayNameForUi(
      profile.publicDisplayLabel,
      accountEmail: widget.isAuthUserDoc && !widget.actingAsOrganization ? me.email : null,
    );
    context.push(
      '/chat/$id',
      extra: ChatScreenRouteExtra(otherUserId: profile.uid, otherDisplayName: otherName),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    context.go('/sign-in');
  }

  Widget _buildAvatarStack(String headerName) {
    return SizedBox(
      width: 128,
      height: 128,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: ClipOval(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _Avatar(photoUrl: profile.photoUrl, name: headerName),
                      if (_uploadingPhoto)
                        ColoredBox(
                          color: Colors.black26,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (widget.isAuthUserDoc && !widget.actingAsOrganization)
            Positioned(
              right: -2,
              bottom: -2,
              child: Material(
                color: _editFabGreen,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _uploadingPhoto ? null : () => _pickAndUploadProfilePhoto(),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      Icons.add_a_photo,
                      color: _uploadingPhoto ? Colors.white54 : Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = FirebaseAuth.instance.currentUser;
    final showOwnEmailHint = widget.isAuthUserDoc && !widget.actingAsOrganization;
    final headerName = UserProfile.displayNameForUi(
      profile.publicDisplayLabel,
      accountEmail: showOwnEmailHint ? me?.email : null,
    );
    final sinceYear = profile.createdAt?.year;
    final city = profile.homeCityLabel?.trim();
    final nb = profile.neighborhoodLabel?.trim();
    final primaryLocation = (city != null && city.isNotEmpty)
        ? city
        : (nb != null && nb.isNotEmpty)
        ? nb
        : 'Neighbor';
    final subtitle = [primaryLocation, if (sinceYear != null) 'Since $sinceYear'].join(' • ');

    final serif = GoogleFonts.playfairDisplay;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              Center(child: _buildAvatarStack(headerName)),
              const SizedBox(height: 20),
              Consumer<ViewAsController>(
                builder: (context, viewAs, _) {
                  if (widget.fromProfileTab && viewAs.staffOrganizations.isNotEmpty) {
                    return const ViewAsIdentityMenu(
                      placement: ViewAsIdentityPlacement.profileBelowAvatar,
                    );
                  }
                  return Text(
                    headerName,
                    textAlign: TextAlign.center,
                    style: serif(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                      height: 1.15,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _slateSubtitle,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (profile.bio != null && profile.bio!.trim().isNotEmpty) ...[
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Bio',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _slateSubtitle,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  profile.bio!.trim(),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _buildPrimaryProfileActions(context, theme),
              const SizedBox(height: 12),
              if (!widget.isAuthUserDoc && !(widget.fromProfileTab && widget.actingAsOrganization))
                ProfileConnectionButton(
                  otherUid: profile.uid,
                  otherDisplayName: profile.publicDisplayLabel,
                ),
              const SizedBox(height: 28),
              _ConnectionsMetricCard(
                userId: profile.uid,
                tappable: widget.isAuthUserDoc && !widget.actingAsOrganization,
              ),
              const SizedBox(height: 16),
              _ProfileMetricCard(
                value: '${profile.eventsAttended}',
                label: 'EVENTS ATTENDED',
                valueColor: _headerGreen,
              ),
              const SizedBox(height: 16),
              _ProfileMetricCard(
                value: '${profile.requestsFulfilled}',
                label: 'REQUESTS FULFILLED',
                valueColor: _statBlue,
              ),
              if (widget.isAuthUserDoc &&
                  !widget.actingAsOrganization &&
                  (profile.accountType == UserAccountType.nonprofit ||
                      profile.accountType == UserAccountType.business)) ...[
                const SizedBox(height: 16),
                _StaffEntryCard(
                  onTap: () => context.push('/profile/staff'),
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Posts',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _slateSubtitle,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<KindredPost>>(
                stream: context.read<PostService>().postsByAuthorId(profile.uid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final posts = snap.data ?? [];
                  if (posts.isEmpty) {
                    return Text(
                      'No posts yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: _slateSubtitle),
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < posts.length; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: i < posts.length - 1 ? 12 : 0),
                          child: _ProfileAuthorPostCard(post: posts[i]),
                        ),
                    ],
                  );
                },
              ),
              if (widget.fromProfileTab) ...[
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => _signOut(context),
                  icon: Icon(Icons.logout, size: 20, color: _slateSubtitle),
                  label: Text(
                    'Log out',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: _slateSubtitle,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAuthorPostCard extends StatelessWidget {
  const _ProfileAuthorPostCard({required this.post});

  final KindredPost post;

  void _open(BuildContext context) {
    if (post.kind == PostKind.communityEvent) {
      context.push('/event/${post.id}');
    } else {
      context.push('/posts/${post.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat.yMMMd().format(post.createdAt);
    final preview = post.body?.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PostKindIconBadge(kind: post.kind, compact: true),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      postKindListHeadline(post.kind),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w700,
                        color: _slateSubtitle,
                      ),
                    ),
                  ),
                  Text(
                    dateStr,
                    style: theme.textTheme.labelSmall?.copyWith(color: _slateSubtitle),
                  ),
                ],
              ),
              if (post.status == PostStatus.fulfilled) ...[
                const SizedBox(height: 6),
                Text(
                  'FULFILLED',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                    color: _slateSubtitle,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                post.title,
                style: GoogleFonts.lora(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: const Color(0xFF141414),
                ),
              ),
              if (preview != null && preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  preview.replaceAll(RegExp(r'\s+'), ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _slateSubtitle,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffEntryCard extends StatelessWidget {
  const _StaffEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.groups_outlined, color: _headerGreen, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STAFF',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _slateSubtitle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Invite teammates by email',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: _slateSubtitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl, required this.name});

  final String? photoUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _Initials(name: name),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const ColoredBox(
            color: Color(0xFFDDE8E0),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }
    return _Initials(name: name);
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final String initials;
    if (parts.isEmpty) {
      initials = '?';
    } else if (parts.length == 1) {
      final s = parts.first;
      initials = s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    } else {
      initials = '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return ColoredBox(
      color: const Color(0xFFDDE8E0),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.playfairDisplay(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            color: _headerGreen,
          ),
        ),
      ),
    );
  }
}

class _ProfileMetricCard extends StatelessWidget {
  const _ProfileMetricCard({required this.value, required this.label, required this.valueColor});

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.playfairDisplay(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6B6B6B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionsMetricCard extends StatelessWidget {
  const _ConnectionsMetricCard({required this.userId, required this.tappable});

  final String userId;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ConnectionService>();
    return StreamBuilder<int>(
      stream: svc.connectionCountStream(userId),
      builder: (context, snap) {
        final n = snap.data ?? 0;
        final card = Stack(
          clipBehavior: Clip.none,
          children: [
            _ProfileMetricCard(value: '$n', label: 'CONNECTIONS', valueColor: _headerGreen),
            if (tappable)
              Positioned(
                top: 10,
                right: 10,
                child: StreamBuilder<int>(
                  stream: svc.incomingRequestCountStream(),
                  builder: (context, pendingSnap) {
                    final pending = pendingSnap.data ?? 0;
                    if (pending <= 0) return const SizedBox.shrink();
                    return PendingConnectionRequestsBadge(count: pending);
                  },
                ),
              ),
          ],
        );
        if (!tappable) return card;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/connections'),
            child: card,
          ),
        );
      },
    );
  }
}

class _ProfileEditSheet extends StatefulWidget {
  const _ProfileEditSheet({required this.profile});

  final UserProfile profile;

  @override
  State<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<_ProfileEditSheet> {
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _entityName;
  late final TextEditingController _bio;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _firstName = TextEditingController(text: p.firstName ?? '');
    _lastName = TextEditingController(text: p.lastName ?? '');
    _entityName = TextEditingController(
      text: p.accountType == UserAccountType.nonprofit
          ? (p.organizationName ?? '')
          : p.accountType == UserAccountType.business
              ? (p.businessName ?? '')
              : '',
    );
    _bio = TextEditingController(text: p.bio ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _entityName.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _openSetHomeAreaWithProfile(UserProfile p) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SetHomeAreaSheet(profile: p),
    );
  }

  Future<void> _save() async {
    final p = widget.profile;
    final t = p.accountType;
    if (t == UserAccountType.personal) {
      if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('First and last name are required.')),
        );
        return;
      }
    } else if (t == UserAccountType.nonprofit) {
      if (_entityName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization name is required.')),
        );
        return;
      }
    } else if (t == UserAccountType.business) {
      if (_entityName.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business name is required.')),
        );
        return;
      }
    }
    final svc = context.read<UserProfileService>();
    try {
      await svc.updatePublicProfile(
        accountType: t,
        firstName: t == UserAccountType.personal ? _firstName.text : null,
        lastName: t == UserAccountType.personal ? _lastName.text : null,
        organizationName: t == UserAccountType.nonprofit ? _entityName.text : null,
        businessName: t == UserAccountType.business ? _entityName.text : null,
        photoUrl: p.photoUrl?.trim().isNotEmpty == true ? p.photoUrl : null,
        bio: _bio.text.trim().isEmpty ? null : _bio.text,
        neighborhoodLabel: p.neighborhoodLabel?.trim().isNotEmpty == true
            ? p.neighborhoodLabel
            : null,
        eventsAttended: p.eventsAttended,
        requestsFulfilled: p.requestsFulfilled,
        eventsProgressNote: p.eventsProgressNote,
        requestsProgressNote: p.requestsProgressNote,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final profileStream = context.read<UserProfileService>().profileStream(widget.profile.uid);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: StreamBuilder<UserProfile?>(
          stream: profileStream,
          initialData: widget.profile,
          builder: (context, snap) {
            final live = snap.data ?? widget.profile;
            final at = live.accountType;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  'Edit profile',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                if (at == UserAccountType.personal) ...[
                  TextField(
                    controller: _firstName,
                    decoration: const InputDecoration(labelText: 'First name'),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lastName,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ] else ...[
                  TextField(
                    controller: _entityName,
                    decoration: InputDecoration(
                      labelText: at == UserAccountType.nonprofit
                          ? 'Organization name'
                          : 'Business name',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _bio,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'A few words about you…',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  minLines: 3,
                  maxLength: UserProfileService.maxBioLength,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openSetHomeAreaWithProfile(live)),
                  icon: const Icon(Icons.location_city),
                  label: Text(
                    _homeAreaEditButtonLabel(live),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _headerGreen,
                    side: const BorderSide(color: _headerGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _headerGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
