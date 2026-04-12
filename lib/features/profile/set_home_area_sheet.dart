import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/user_profile.dart';
import '../../core/services/location_search_service.dart';
import '../../core/services/user_profile_service.dart';

const _headerGreen = Color(0xFF2E7D5A);

/// Sets [UserProfile.homeGeoPoint], [homeCityLabel], and [discoveryRadiusMiles] from a single city search.
/// Typing shows suggestions; choosing one locks coordinates to the same place as the label.
class SetHomeAreaSheet extends StatefulWidget {
  const SetHomeAreaSheet({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<SetHomeAreaSheet> createState() => _SetHomeAreaSheetState();
}

class _SetHomeAreaSheetState extends State<SetHomeAreaSheet> {
  late final TextEditingController _city;
  late final FocusNode _focus;
  late int _radius;
  GeoSearchResult? _selected;
  bool _busy = false;

  UserProfile get _p => widget.profile;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _radius = _p.discoveryRadiusMiles.clamp(10, 100);
    final initial = _p.homeCityLabel?.trim().isNotEmpty == true
        ? _p.homeCityLabel!.trim()
        : (_p.neighborhoodLabel?.trim().isNotEmpty == true ? _p.neighborhoodLabel!.trim() : '');
    _city = TextEditingController(text: initial);
    _city.addListener(_onCityTextChanged);
    if (_p.homeGeoPoint != null && initial.isNotEmpty) {
      _selected = GeoSearchResult(label: initial, geoPoint: _p.homeGeoPoint!);
    }
  }

  void _onCityTextChanged() {
    if (_selected != null && _city.text.trim() != _selected!.label) {
      setState(() => _selected = null);
    }
  }

  @override
  void dispose() {
    _city.removeListener(_onCityTextChanged);
    _city.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<GeoSearchResult>> _optionsBuilder(TextEditingValue value) async {
    final q = value.text.trim();
    if (q.length < 2) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_city.text.trim() != q) return const [];
    return LocationSearchService.search(q);
  }

  Future<void> _save() async {
    final resolved = _selected;
    if (resolved == null) return;

    final svc = context.read<UserProfileService>();
    setState(() => _busy = true);
    try {
      await svc.updateHomeAndRadius(
        homeGeoPoint: resolved.geoPoint,
        discoveryRadiusMiles: _radius,
        homeCityLabel: resolved.label,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Home area saved. Local feeds use this point and radius.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            Text(
              'Home area',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for your city or neighborhood, choose a result, then save. '
              'We store the place name and coordinates together for local discovery.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Search: Photon (Komoot) · data © OpenStreetMap contributors.',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            RawAutocomplete<GeoSearchResult>(
              displayStringForOption: (o) => o.label,
              textEditingController: _city,
              focusNode: _focus,
              optionsBuilder: _optionsBuilder,
              onSelected: (GeoSearchResult o) {
                setState(() => _selected = o);
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'City or area',
                    hintText: 'Start typing…',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => onFieldSubmitted(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220, minWidth: 280),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final o = options.elementAt(i);
                          return ListTile(
                            title: Text(o.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                            dense: true,
                            onTap: () => onSelected(o),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_selected != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: _headerGreen),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Using: ${_selected!.label}',
                      style: theme.textTheme.bodySmall?.copyWith(color: _headerGreen, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Radius', style: theme.textTheme.titleSmall),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: _radius.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    label: '$_radius mi',
                    onChanged: (v) => setState(() => _radius = v.round()),
                  ),
                ),
                Text('$_radius mi', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (_busy || _selected == null) ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: _headerGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save home area'),
            ),
          ],
        ),
      ),
    );
  }
}
