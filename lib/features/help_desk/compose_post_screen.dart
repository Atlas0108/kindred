import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/kindred_scaffold_messenger.dart';
import '../../core/constants/default_geo.dart';
import '../../core/constants/tag_presets.dart';
import '../../core/kindred_trace.dart';
import '../../core/models/post_kind.dart';
import '../../core/services/post_service.dart';
import '../../core/services/user_profile_service.dart';

class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key, this.initialDeskKind});

  /// When set (from `/compose?kind=offer` or `request`), pre-selects help request vs offer.
  final PostKind? initialDeskKind;

  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late bool _needHelp;
  final Set<String> _tags = {};
  GeoPoint _postGeo = kDefaultGeoPoint;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final k = widget.initialDeskKind;
    _needHelp = k == null
        ? true
        : k == PostKind.helpRequest
            ? true
            : false;
    _postGeo = kDefaultGeoPoint;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      unawaited(_applyHomeGeo(u.uid));
    });
  }

  Future<void> _applyHomeGeo(String uid) async {
    try {
      final p = await context.read<UserProfileService>().fetchProfile(uid);
      if (!mounted) return;
      final home = p?.homeGeoPoint;
      if (home != null) {
        setState(() => _postGeo = home);
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

  Future<void> _publish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a title.')),
      );
      return;
    }
    kindredTrace('ComposePostScreen._publish start');
    setState(() => _busy = true);
    try {
      final kind = _needHelp ? PostKind.helpRequest : PostKind.helpOffer;
      kindredTrace('ComposePostScreen._publish calling PostService.createPost', '$kind');
      final id = await context.read<PostService>().createPost(
            kind: kind,
            title: _title.text.trim(),
            body: _body.text.trim().isEmpty ? null : _body.text.trim(),
            tags: _tags.toList(),
            geoPoint: _postGeo,
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
        title: const Text('New post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: user == null
          ? const Center(child: Text('Sign in required'))
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
                  const SizedBox(height: 16),
                  Text('Tags', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...kTagPresets.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: Theme.of(context).textTheme.labelLarge),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: e.value.map((tag) {
                              final selected = _tags.contains(tag);
                              return FilterChip(
                                label: Text(tag),
                                selected: selected,
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    _tags.add(tag);
                                  } else {
                                    _tags.remove(tag);
                                  }
                                }),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    'Discovery uses your profile home if set; otherwise a default area.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
                        : const Text('Post'),
                  ),
                ],
              ),
            ),
    );
  }
}
