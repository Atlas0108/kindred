import 'package:flutter/material.dart';

import '../core/services/location_search_service.dart';

/// Photon-backed city/area search; same behavior as profile / home feed pickers.
class CitySearchField extends StatefulWidget {
  const CitySearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration = const InputDecoration(
      labelText: 'City or area',
      hintText: 'Start typing…',
      border: OutlineInputBorder(),
    ),
    this.showAttribution = true,
  });

  /// Current map center; `null` after the user edits the field without picking a suggestion.
  final GeoSearchResult? value;

  final ValueChanged<GeoSearchResult?> onChanged;

  final InputDecoration decoration;

  final bool showAttribution;

  @override
  State<CitySearchField> createState() => _CitySearchFieldState();
}

class _CitySearchFieldState extends State<CitySearchField> {
  late final TextEditingController _city;
  late final FocusNode _focus;
  GeoSearchResult? _selected;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    final v = widget.value;
    _city = TextEditingController(text: v?.label ?? '');
    _selected = v;
    _city.addListener(_onCityTextChanged);
  }

  @override
  void didUpdateWidget(CitySearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = widget.value;
    final b = oldWidget.value;
    if (a == null && b != null) {
      return;
    }
    if (a != null &&
        (b == null ||
            a.label != b.label ||
            a.geoPoint.latitude != b.geoPoint.latitude ||
            a.geoPoint.longitude != b.geoPoint.longitude)) {
      _selected = a;
      _city.text = a.label;
      _city.selection = TextSelection.collapsed(offset: _city.text.length);
    }
  }

  void _onCityTextChanged() {
    if (_selected != null && _city.text.trim() != _selected!.label) {
      setState(() => _selected = null);
      widget.onChanged(null);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RawAutocomplete<GeoSearchResult>(
          displayStringForOption: (o) => o.label,
          textEditingController: _city,
          focusNode: _focus,
          optionsBuilder: _optionsBuilder,
          onSelected: (GeoSearchResult o) {
            setState(() => _selected = o);
            widget.onChanged(o);
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: widget.decoration,
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
        if (widget.showAttribution) ...[
          const SizedBox(height: 6),
          Text(
            'Search: Photon (Komoot) · data © OpenStreetMap contributors.',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }
}
