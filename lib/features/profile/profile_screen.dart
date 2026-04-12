import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/models/user_profile.dart';
import '../../core/services/messaging_service.dart';
import '../../core/services/user_profile_service.dart';
import '../inbox/chat_screen.dart';
import '../../core/utils/blob_from_object_url.dart';

/// Matches the Kindred home cream canvas.
const _pageBackground = Color(0xFFF9F7F2);

const _headerGreen = Color(0xFF2E7D5A);
const _editFabGreen = Color(0xFF1F5C40);
const _slateSubtitle = Color(0xFF5B6B7A);
const _tagGreenBg = Color(0xFFE8F3EB);
const _tagGreenFg = Color(0xFF1B4D32);
const _tagBlueBg = Color(0xFFE8EEF5);
const _tagBlueFg = Color(0xFF2A4A6A);
const _statBlue = Color(0xFF3D5A80);
const _gearBg = Color(0xFFECECEA);
const _gearIcon = Color(0xFF5C5C5C);

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
      return const Scaffold(
        body: Center(child: Text('Sign in to view your profile.')),
      );
    }

    final targetUid = widget.userId ?? user.uid;
    final svc = context.read<UserProfileService>();
    final fromShell = widget.userId == null;

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
              final viewingSelf = targetUid == user.uid;
              if (viewingSelf) {
                final email = user.email?.trim();
                if (email == null || email.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add an email address to your account to show your profile.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: _slateSubtitle),
                      ),
                    ),
                  );
                }
                if (!_selfEnsureRequested) {
                  _selfEnsureRequested = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    unawaited(
                      svc.ensureProfile(
                        displayName: UserProfileService.preferredDisplayNameFromAuthUser(user),
                      ),
                    );
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
            final selfUid = user.uid;
            final viewingSelf = selfUid == p.uid;
            return _ProfileBody(key: ValueKey(p.uid), profile: p, viewingSelf: viewingSelf);
          },
        ),
      ),
    );

    if (fromShell) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: body,
    );
  }
}

class _ProfileBody extends StatefulWidget {
  const _ProfileBody({super.key, required this.profile, required this.viewingSelf});

  final UserProfile profile;
  final bool viewingSelf;

  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> {
  bool _uploadingPhoto = false;

  UserProfile get profile => widget.profile;

  static double _eventsProgress(int n) => (n / 16).clamp(0.0, 1.0);
  static double _requestsProgress(int n) => (n / 12).clamp(0.0, 1.0);

  void _openEdit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProfileEditSheet(profile: widget.profile),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update photo: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _openChat(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final id = MessagingService.conversationIdForPair(me.uid, profile.uid);
    context.push(
      '/chat/$id',
      extra: ChatScreenRouteExtra(
        otherUserId: profile.uid,
        otherDisplayName: profile.displayName,
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    context.go('/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sinceYear = profile.createdAt?.year;
    final subtitle = [
      if (profile.neighborhoodLabel != null && profile.neighborhoodLabel!.isNotEmpty)
        profile.neighborhoodLabel!
      else
        'Neighbor',
      if (sinceYear != null) 'Since $sinceYear',
    ].join(' • ');

    final serif = GoogleFonts.playfairDisplay;
    final tags = profile.profileTags;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              SizedBox(
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
                                _Avatar(photoUrl: profile.photoUrl, name: profile.displayName),
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
                    if (widget.viewingSelf)
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
              ),
              const SizedBox(height: 20),
              Text(
                profile.displayName,
                textAlign: TextAlign.center,
                style: serif(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                  height: 1.15,
                ),
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
              const SizedBox(height: 16),
              ...List.generate(tags.length.clamp(0, 3), (i) {
                final t = tags[i];
                final green = i % 2 == 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: green ? _tagGreenBg : _tagBlueBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      t.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: green ? _tagGreenFg : _tagBlueFg,
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.viewingSelf
                          ? () => context.go('/inbox')
                          : () => _openChat(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: _headerGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: widget.viewingSelf ? const Text('Inbox') : const Text('Message'),
                    ),
                  ),
                  if (widget.viewingSelf) ...[
                    const SizedBox(width: 12),
                    Material(
                      color: _gearBg,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _openEdit(context),
                        child: const SizedBox(
                          width: 52,
                          height: 52,
                          child: Icon(Icons.settings, color: _gearIcon),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 28),
              _StatCard(
                value: '${profile.eventsAttended}',
                label: 'EVENTS ATTENDED',
                valueColor: _headerGreen,
                progress: _eventsProgress(profile.eventsAttended),
                gradientColors: const [Color(0xFF9BC9A8), Color(0xFF2E7D5A)],
                caption: profile.eventsProgressNote?.isNotEmpty == true
                    ? profile.eventsProgressNote!
                    : 'Top 5% active members',
              ),
              const SizedBox(height: 16),
              _StatCard(
                value: '${profile.requestsFulfilled}',
                label: 'REQUESTS FULFILLED',
                valueColor: _statBlue,
                progress: _requestsProgress(profile.requestsFulfilled),
                gradientColors: const [Color(0xFF9BB4D4), Color(0xFF3D5A80)],
                caption: profile.requestsProgressNote?.isNotEmpty == true
                    ? profile.requestsProgressNote!
                    : 'Silver helper badge',
              ),
              if (widget.viewingSelf) ...[
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.progress,
    required this.gradientColors,
    required this.caption,
  });

  final String value;
  final String label;
  final Color valueColor;
  final double progress;
  final List<Color> gradientColors;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
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
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: Colors.grey.shade200),
                  FractionallySizedBox(
                    widthFactor: progress,
                    alignment: Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
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
  late final TextEditingController _name;
  late final TextEditingController _neighborhood;
  late final TextEditingController _photoUrl;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.displayName);
    _neighborhood = TextEditingController(text: p.neighborhoodLabel ?? '');
    _photoUrl = TextEditingController(text: p.photoUrl ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _neighborhood.dispose();
    _photoUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final svc = context.read<UserProfileService>();
    final p = widget.profile;
    try {
      await svc.updatePublicProfile(
        displayName: _name.text,
        photoUrl: _photoUrl.text.trim().isEmpty ? null : _photoUrl.text,
        neighborhoodLabel: _neighborhood.text.trim().isEmpty ? null : _neighborhood.text,
        profileTags: p.profileTags,
        eventsAttended: p.eventsAttended,
        requestsFulfilled: p.requestsFulfilled,
        eventsProgressNote: p.eventsProgressNote,
        requestsProgressNote: p.requestsProgressNote,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
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
            Text('Edit profile', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Display name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _neighborhood,
              decoration: const InputDecoration(
                labelText: 'Neighborhood label',
                hintText: 'e.g. Oak Creek Neighbor',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _photoUrl,
              decoration: const InputDecoration(
                labelText: 'Photo URL (optional)',
                hintText: 'https://…',
              ),
              keyboardType: TextInputType.url,
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
        ),
      ),
    );
  }
}
