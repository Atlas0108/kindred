import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app/kindred_scaffold_messenger.dart';
import '../../app/view_as_controller.dart';
import '../../core/config/dev_compose_prefills.dart';
import '../../core/constants/default_geo.dart';
import '../../core/kindred_trace.dart';
import '../../core/models/post.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/location_search_service.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/blob_from_object_url.dart';
import '../../widgets/city_search_field.dart';

class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key, this.initialDeskKind, this.editingPostId});

  /// When set (from `/compose?kind=offer` or `request`), pre-selects help request vs offer.
  final PostKind? initialDeskKind;

  /// When set (from `/posts/:id/edit`), loads that post for editing (author only).
  final String? editingPostId;

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late bool _needHelp;
  GeoSearchResult? _postMapLocation;
  bool _busy = false;
  XFile? _pickedXFile;
  Uint8List? _pickedImageBytes;
  String? _pickedImageMime;

  KindredPost? _editingPost;
  bool _loadingEdit = false;
  bool _removeExistingCover = false;
  String? _existingCoverUrl;

  bool get _isEditMode => widget.editingPostId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _loadingEdit = true;
      _needHelp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPostForEdit());
    } else {
      final k = widget.initialDeskKind;
      _needHelp = k == null
          ? true
          : k == PostKind.helpRequest
              ? true
              : false;
      _postMapLocation = GeoSearchResult(
        label: 'San Francisco area',
        geoPoint: kDefaultGeoPoint,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyDevPrefills();
        final u = FirebaseAuth.instance.currentUser;
        if (u == null) return;
        unawaited(_applyHomeGeo(u.uid));
      });
    }
  }

  void _applyDevPrefills() {
    if (!dotenv.isInitialized) return;
    if (_needHelp) {
      DevComposePrefills.applyHelpRequest(title: _title, body: _body);
    } else {
      DevComposePrefills.applyHelpOffer(title: _title, body: _body);
    }
    setState(() {});
  }

  Future<void> _loadPostForEdit() async {
    final id = widget.editingPostId;
    if (id == null || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.pop();
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('posts').doc(id).get();
      if (!mounted) return;
      final p = KindredPost.fromDoc(snap);
      if (p == null || p.authorId != user.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can only edit your own posts.')),
        );
        context.pop();
        return;
      }
      final url = p.imageUrl?.trim();
      setState(() {
        _editingPost = p;
        _title.text = p.title;
        _body.text = p.body ?? '';
        _needHelp = p.kind == PostKind.helpRequest;
        final locDesc = p.locationDescription?.trim();
        _postMapLocation = GeoSearchResult(
          geoPoint: p.geoPoint,
          label: locDesc != null && locDesc.isNotEmpty
              ? locDesc.replaceAll(RegExp(r'\s+'), ' ')
              : 'Saved post location',
        );
        _existingCoverUrl = url != null && url.isNotEmpty ? url : null;
        _removeExistingCover = false;
        _loadingEdit = false;
      });
    } catch (e) {
      kindredTrace('ComposePostScreen._loadPostForEdit', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        context.pop();
      }
    }
  }

  Future<void> _applyHomeGeo(String uid) async {
    try {
      final p = await context.read<UserProfileService>().fetchProfile(uid);
      if (!mounted) return;
      final home = p?.homeGeoPoint;
      if (home != null) {
        final label = p?.homeCityLabel?.trim();
        setState(() {
          _postMapLocation = GeoSearchResult(
            geoPoint: home,
            label: label != null && label.isNotEmpty ? label : 'Home',
          );
        });
      }
    } on Exception catch (e) {
      kindredTrace('ComposePostScreen._applyHomeGeo error', e);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 78,
    );
    if (x == null) return;
    if (!mounted) return;
    if (kIsWeb) {
      setState(() {
        _pickedXFile = x;
        _pickedImageBytes = null;
        _pickedImageMime = x.mimeType;
        _removeExistingCover = false;
        _existingCoverUrl = null;
      });
    } else {
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedXFile = null;
        _pickedImageBytes = bytes;
        _pickedImageMime = x.mimeType;
        _removeExistingCover = false;
        _existingCoverUrl = null;
      });
    }
  }

  void _clearImage() {
    setState(() {
      _pickedXFile = null;
      _pickedImageBytes = null;
      _pickedImageMime = null;
      if (_editingPost != null && _existingCoverUrl != null) {
        _removeExistingCover = true;
        _existingCoverUrl = null;
      }
    });
  }

  bool get _hasPickedImage =>
      _pickedImageBytes != null || (kIsWeb && _pickedXFile != null);

  bool get _showingCover =>
      _hasPickedImage || (_existingCoverUrl != null && !_removeExistingCover);

  Future<void> _publish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title.')),
      );
      return;
    }
    final place = _postMapLocation;
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a city or area from the search suggestions.'),
        ),
      );
      return;
    }
    kindredTrace('ComposePostScreen._publish start');
    setState(() => _busy = true);
    try {
      final kind = _needHelp ? PostKind.helpRequest : PostKind.helpOffer;
      Object? webBlob;
      Uint8List? imageBytes = _pickedImageBytes;
      if (kIsWeb && _pickedXFile != null) {
        kindredTrace('ComposePostScreen._publish resolving web Blob');
        webBlob = await blobFromObjectUrl(_pickedXFile!.path);
        if (webBlob != null) {
          imageBytes = null;
        } else {
          kindredTrace('ComposePostScreen._publish blob URL fetch failed, using bytes');
          imageBytes = await _pickedXFile!.readAsBytes();
        }
      }
      if (!mounted) return;

      final editing = _editingPost;
      if (editing != null) {
        kindredTrace('ComposePostScreen._publish calling PostService.updatePost', '$kind');
        await context.read<PostService>().updatePost(
              post: editing,
              kind: kind,
              title: _title.text.trim(),
              body: _body.text.trim().isEmpty ? null : _body.text.trim(),
              geoPoint: place.geoPoint,
              userRemovedCover: _removeExistingCover && !_hasPickedImage,
              newCoverBytes: imageBytes,
              newCoverWebBlob: webBlob,
              newCoverContentType: _pickedImageMime,
            );
        if (!mounted) return;
        if (!context.mounted) return;
        context.pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          kindredScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Post updated')),
          );
        });
      } else {
        kindredTrace('ComposePostScreen._publish calling PostService.createPost', '$kind');
        final viewAs = context.read<ViewAsController>();
        final postSvc = context.read<PostService>();
        final profileSvc = context.read<UserProfileService>();
        final orgUid = viewAs.actingOrganizationUid;
        String? postAsUid;
        String? postAsName;
        if (orgUid != null) {
          await profileSvc.assertCurrentUserMayActAsOrganization(orgUid);
          final prof = await profileSvc.fetchProfile(orgUid);
          postAsUid = orgUid;
          postAsName = prof?.publicDisplayLabel ?? 'Organization';
        }
        final id = await postSvc.createPost(
              kind: kind,
              title: _title.text.trim(),
              body: _body.text.trim().isEmpty ? null : _body.text.trim(),
              geoPoint: place.geoPoint,
              imageBytes: imageBytes,
              imageContentType: _pickedImageMime,
              webImageBlob: webBlob,
              postAsAuthorUid: postAsUid,
              postAsAuthorName: postAsName,
            );
        kindredTrace('ComposePostScreen._publish createPost returned', id);
        if (!mounted) return;
        if (!context.mounted) return;
        context.go('/home');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          kindredScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Post published')),
          );
        });
      }
    } catch (e, st) {
      kindredTrace('ComposePostScreen._publish catch', e);
      assert(() {
        kindredTrace('ComposePostScreen._publish stack', st);
        return true;
      }());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      kindredTrace('ComposePostScreen._publish finally');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit post' : 'New post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: user == null
          ? const Center(child: Text('Sign in required'))
          : _loadingEdit
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('I need help')),
                      ButtonSegment(value: false, label: Text('I can help')),
                    ],
                    selected: {_needHelp},
                    onSelectionChanged: (s) => setState(() => _needHelp = s.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Title'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _body,
                    decoration: const InputDecoration(labelText: 'Details (optional)'),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 20),
                  Text('City or area', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Used for nearby feeds and discovery. Pick a suggestion from the list.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (!_loadingEdit)
                    CitySearchField(
                      value: _postMapLocation,
                      onChanged: (v) => setState(() => _postMapLocation = v),
                      decoration: const InputDecoration(
                        labelText: 'Search city or neighborhood',
                        hintText: 'Start typing…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text('Photo (optional)', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (_showingCover) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: _hasPickedImage
                            ? (kIsWeb && _pickedXFile != null
                                ? Image.network(
                                    _pickedXFile!.path,
                                    fit: BoxFit.cover,
                                  )
                                : Image.memory(
                                    _pickedImageBytes!,
                                    fit: BoxFit.cover,
                                  ))
                            : Image.network(
                                _existingCoverUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: Colors.grey.shade300,
                                  child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _clearImage,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo'),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(_isEditMode ? 'Change photo' : 'Add photo'),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _publish,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEditMode ? 'Save' : 'Post'),
                  ),
                ],
              ),
            ),
    );
  }
}
