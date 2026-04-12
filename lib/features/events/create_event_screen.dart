import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/kindred_scaffold_messenger.dart';
import '../../core/config/dev_compose_prefills.dart';
import '../../core/constants/default_geo.dart';
import '../../core/constants/event_tag_presets.dart';
import '../../core/kindred_trace.dart';
import '../../core/models/community_event.dart';
import '../../core/services/event_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../core/utils/blob_from_object_url.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key, this.editingEventId});

  /// When set (from `/event/:id/edit`), loads that event for editing (organizer only).
  final String? editingEventId;

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _title = TextEditingController();
  final _organizer = TextEditingController();
  final _description = TextEditingController();
  final _locationText = TextEditingController();
  final Set<String> _tags = {};
  late DateTime _startsAt;
  late DateTime _endsAt;
  /// For discovery radius queries; optional home from profile replaces default.
  GeoPoint _discoveryGeo = kDefaultGeoPoint;
  bool _busy = false;
  XFile? _pickedXFile;
  Uint8List? _pickedImageBytes;
  String? _pickedImageMime;

  CommunityEvent? _editingEvent;
  bool _loadingEdit = false;
  bool _removeExistingCover = false;
  String? _existingCoverUrl;

  bool get _isEditMode => widget.editingEventId != null;

  @override
  void initState() {
    super.initState();
    final base = DateTime.now().add(const Duration(days: 1));
    _startsAt = DateTime(base.year, base.month, base.day, base.hour.clamp(0, 23), 0);
    _endsAt = _startsAt.add(const Duration(hours: 1));
    _discoveryGeo = kDefaultGeoPoint;
    if (_isEditMode) {
      _loadingEdit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEventForEdit());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        kindredTrace('CreateEventScreen postFrameCallback');
        if (!mounted) return;
        final u = FirebaseAuth.instance.currentUser;
        if (u == null) {
          kindredTrace('CreateEventScreen postFrameCallback no user');
          return;
        }
        unawaited(_bootstrapNewEventForm(u.uid));
      });
    }
  }

  Future<void> _bootstrapNewEventForm(String uid) async {
    await _applyProfileDefaults(uid);
    if (!mounted) return;
    DevComposePrefills.applyNewEvent(
      title: _title,
      organizer: _organizer,
      description: _description,
      location: _locationText,
      tags: _tags,
    );
    if (mounted) setState(() {});
  }

  Future<void> _loadEventForEdit() async {
    final id = widget.editingEventId;
    if (id == null || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.pop();
      return;
    }
    try {
      final e = await context.read<EventService>().fetchEvent(id);
      if (!mounted) return;
      if (e == null || e.organizerId != user.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You can only edit your own events.')),
        );
        context.pop();
        return;
      }
      final end = e.endsAt ?? e.startsAt.add(const Duration(hours: 1));
      final url = e.imageUrl?.trim();
      setState(() {
        _editingEvent = e;
        _title.text = e.title;
        _organizer.text = e.organizerName;
        _description.text = e.description;
        _locationText.text = e.locationDescription;
        _startsAt = e.startsAt.toLocal();
        _endsAt = end.toLocal();
        _tags
          ..clear()
          ..addAll(e.tags);
        _discoveryGeo = e.geoPoint;
        _existingCoverUrl = url != null && url.isNotEmpty ? url : null;
        _removeExistingCover = false;
        _loadingEdit = false;
      });
    } catch (e, st) {
      kindredTrace('CreateEventScreen._loadEventForEdit', e);
      assert(() {
        kindredTrace('CreateEventScreen._loadEventForEdit stack', st);
        return true;
      }());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        context.pop();
      }
    }
  }

  /// Best-effort: never block the form on Firestore (offline / slow get() otherwise spins forever).
  Future<void> _applyProfileDefaults(String uid) async {
    kindredTrace('CreateEventScreen._applyProfileDefaults start', uid);
    try {
      final p = await context.read<UserProfileService>().fetchProfile(uid);
      kindredTrace('CreateEventScreen._applyProfileDefaults fetchProfile done', '${p != null}');
      if (!mounted) return;
      setState(() {
        final home = p?.homeGeoPoint;
        if (home != null) {
          _discoveryGeo = home;
        }
        final name = p?.displayName.trim();
        if (name != null &&
            name.isNotEmpty &&
            name != 'Neighbor' &&
            _organizer.text.trim().isEmpty) {
          _organizer.text = name;
        }
      });
    } on Exception catch (e, st) {
      kindredTrace('CreateEventScreen._applyProfileDefaults error', e);
      assert(() {
        kindredTrace('CreateEventScreen._applyProfileDefaults stack', st);
        return true;
      }());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _organizer.dispose();
    _description.dispose();
    _locationText.dispose();
    super.dispose();
  }

  Future<void> _pickStartsAt() async {
    final firstDate = _isEditMode
        ? DateTime.now().subtract(const Duration(days: 365 * 10))
        : DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _startsAt.isBefore(firstDate) ? firstDate : _startsAt,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt),
    );
    if (t == null || !mounted) return;
    setState(() {
      _startsAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (!_endsAt.isAfter(_startsAt)) {
        _endsAt = _startsAt.add(const Duration(hours: 1));
      }
    });
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
      if (_editingEvent != null && _existingCoverUrl != null) {
        _removeExistingCover = true;
        _existingCoverUrl = null;
      }
    });
  }

  bool get _hasPickedImage =>
      _pickedImageBytes != null || (kIsWeb && _pickedXFile != null);

  bool get _showingCover =>
      _hasPickedImage || (_existingCoverUrl != null && !_removeExistingCover);

  Future<void> _pickEndsAt() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _endsAt.isBefore(_startsAt) ? _startsAt : _endsAt,
      firstDate: DateTime(_startsAt.year, _startsAt.month, _startsAt.day),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endsAt),
    );
    if (t == null || !mounted) return;
    setState(() {
      _endsAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    final geo = _discoveryGeo;
    final title = _title.text.trim();
    final organizer = _organizer.text.trim();
    final description = _description.text.trim();
    final loc = _locationText.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an event title.')),
      );
      return;
    }
    if (organizer.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add an organizer or group name.')),
      );
      return;
    }
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a description and agenda.')),
      );
      return;
    }
    if (loc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a street address, venue, or virtual meeting link.'),
        ),
      );
      return;
    }
    if (!_endsAt.isAfter(_startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time.')),
      );
      return;
    }

    kindredTrace('CreateEventScreen._save validation OK, set busy');
    setState(() => _busy = true);
    try {
      final tags = _tags.toList()..sort();
      kindredTrace('CreateEventScreen._save calling EventService.createEvent');
      Object? webBlob;
      Uint8List? imageBytes = _pickedImageBytes;
      if (kIsWeb && _pickedXFile != null) {
        kindredTrace('CreateEventScreen._save resolving web Blob');
        webBlob = await blobFromObjectUrl(_pickedXFile!.path);
        if (webBlob != null) {
          imageBytes = null;
        } else {
          kindredTrace('CreateEventScreen._save blob URL fetch failed, using bytes');
          imageBytes = await _pickedXFile!.readAsBytes();
        }
      }
      if (!mounted) return;
      final editing = _editingEvent;
      if (editing != null) {
        kindredTrace('CreateEventScreen._save calling EventService.updateEvent');
        await context.read<EventService>().updateEvent(
              event: editing,
              title: title,
              description: description,
              organizerName: organizer,
              tags: tags,
              startsAt: _startsAt,
              endsAt: _endsAt,
              locationDescription: loc,
              geoPoint: geo,
              userRemovedCover: _removeExistingCover && !_hasPickedImage,
              newCoverBytes: imageBytes,
              newCoverWebBlob: webBlob,
              newCoverContentType: _pickedImageMime,
            );
        kindredTrace('CreateEventScreen._save updateEvent returned');
        if (!mounted) return;
        if (!context.mounted) return;
        context.pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          kindredScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Event updated')),
          );
        });
      } else {
        await context.read<EventService>().createEvent(
              title: title,
              description: description,
              organizerName: organizer,
              tags: tags,
              startsAt: _startsAt,
              endsAt: _endsAt,
              locationDescription: loc,
              geoPoint: geo,
              imageBytes: imageBytes,
              imageContentType: _pickedImageMime,
              webImageBlob: webBlob,
            );
        kindredTrace('CreateEventScreen._save createEvent returned');
        if (!mounted) {
          kindredTrace('CreateEventScreen._save not mounted after create');
          return;
        }
        if (!context.mounted) return;
        kindredTrace('CreateEventScreen._save context.go(/home)');
        context.go('/home');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          kindredScaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Event published')),
          );
        });
      }
    } catch (e, st) {
      kindredTrace('CreateEventScreen._save catch', e);
      assert(() {
        kindredTrace('CreateEventScreen._save stack', st);
        return true;
      }());
      if (!mounted) return;
      final message = _eventSaveErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      kindredTrace('CreateEventScreen._save finally clear busy');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateTimeFmt = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit event' : 'New event'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loadingEdit
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Event title',
                      hintText: 'Short, clear name',
                      helperText: 'Keep it clear and concise.',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _organizer,
                    decoration: const InputDecoration(
                      labelText: 'Organizer name or group',
                      hintText: 'Who is hosting?',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Event description',
                      hintText: 'What to expect, schedule, what to bring…',
                      helperText: 'Details and agenda.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 4,
                    maxLines: 8,
                  ),
                  const SizedBox(height: 20),
                  Text('Cover photo (optional)', style: theme.textTheme.titleSmall),
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
                      label: Text(_isEditMode ? 'Change cover photo' : 'Add cover photo'),
                    ),
                  const SizedBox(height: 20),
                  Text('Category / tags', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'e.g. Social, Educational, Volunteer',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: kEventCategoryTags.map((tag) {
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
                  const SizedBox(height: 20),
                  Text('When', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_circle_outline),
                    title: const Text('Starts'),
                    subtitle: Text(dateTimeFmt.format(_startsAt.toLocal())),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickStartsAt,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.stop_circle_outlined),
                    title: const Text('Ends'),
                    subtitle: Text(dateTimeFmt.format(_endsAt.toLocal())),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickEndsAt,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _locationText,
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'Street address, venue, or paste a virtual meeting link',
                      helperText: 'Physical address or virtual meeting link.',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Discovery uses your profile home location if you have one set; otherwise a default area.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEditMode ? 'Save changes' : 'Publish event'),
                  ),
                ],
              ),
            ),
    );
  }
}

String _eventSaveErrorMessage(Object e) {
  if (e is FirebaseException) {
    if (e.code == 'permission-denied') {
      return 'Permission denied saving the event. Deploy the latest Firestore rules '
          '(events need organizerId, title, description, startsAt, endsAt, tags, etc.).';
    }
    final m = e.message?.trim();
    if (m != null && m.isNotEmpty) return '${e.code}: $m';
    return e.code;
  }
  if (e is TimeoutException) {
    return e.message?.isNotEmpty == true
        ? e.message!
        : 'Timed out. Check your connection and try again.';
  }
  return e.toString();
}
