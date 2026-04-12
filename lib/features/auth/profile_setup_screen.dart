import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/models/user_profile.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/blob_from_object_url.dart';
import '../profile/set_home_area_sheet.dart';

const _headerGreen = Color(0xFF2E7D5A);
const _pageBackground = Color(0xFFF9F7F2);

/// Required: first name, last name, home area ([SetHomeAreaSheet]). Optional: photo, bio.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _bio = TextEditingController();
  bool _saving = false;
  bool _uploadingPhoto = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _bio.dispose();
    super.dispose();
  }

  UserProfile _sheetProfile(User user, UserProfile? fromStream) {
    return fromStream ??
        UserProfile(
          uid: user.uid,
          displayName: 'Neighbor',
          discoveryRadiusMiles: 25,
        );
  }

  Future<void> _openHomeArea(User user, UserProfile? p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SetHomeAreaSheet(profile: _sheetProfile(user, p)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickPhoto() async {
    final svc = context.read<UserProfileService>();
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
      await svc.uploadAndSetProfilePhoto(
        imageBytes: bytes,
        webImageBlob: webBlob,
        imageContentType: mime,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo added')),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _continue(User user, UserProfile? p) async {
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your first and last name.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final svc = context.read<UserProfileService>();
    try {
      await svc.updateProfileNamesAndOptionalBio(
        firstName: _firstName.text,
        lastName: _lastName.text,
        bio: _bio.text.trim().isEmpty ? null : _bio.text,
      );
      final fresh = await svc.fetchProfile(user.uid);
      if (!mounted) return;
      if (fresh == null || !fresh.isProfileSetupComplete) {
        setState(() {
          _error = 'Please set your home area (search and pick a place).';
          _saving = false;
        });
        return;
      }
      if (mounted) setState(() => _saving = false);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in required.')));
    }

    final svc = context.read<UserProfileService>();

    return Scaffold(
      backgroundColor: _pageBackground,
      body: SafeArea(
        child: StreamBuilder<UserProfile?>(
          stream: svc.profileStream(user.uid),
          builder: (context, snap) {
            final p = snap.data;
            final homeOk = p?.homeGeoPoint != null;
            final theme = Theme.of(context);

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Set up your profile',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We need your name and home area so neighbors and local feeds work. '
                        'Photo and bio are optional.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _firstName,
                        decoration: const InputDecoration(labelText: 'First name'),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lastName,
                        decoration: const InputDecoration(labelText: 'Last name'),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _bio,
                        decoration: const InputDecoration(
                          labelText: 'Bio (optional)',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 4,
                        minLines: 2,
                        maxLength: UserProfileService.maxBioLength,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _uploadingPhoto ? null : () => _pickPhoto(),
                        icon: _uploadingPhoto
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_a_photo_outlined),
                        label: Text(_uploadingPhoto ? 'Uploading…' : 'Add profile photo (optional)'),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _openHomeArea(user, p),
                        style: FilledButton.styleFrom(
                          backgroundColor: _headerGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: Icon(homeOk ? Icons.check_circle_outline : Icons.place_outlined),
                        label: Text(
                          homeOk
                              ? 'Home area set — tap to change'
                              : 'Set home area (required)',
                        ),
                      ),
                      if (p?.homeCityLabel != null && p!.homeCityLabel!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          p.homeCityLabel!.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error, height: 1.35),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _continue(user, p),
                        style: FilledButton.styleFrom(
                          backgroundColor: _headerGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Continue'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
