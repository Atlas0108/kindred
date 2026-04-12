/// Curated tags by category for the Help Desk.
const Map<String, List<String>> kTagPresets = {
  'Physical tools': [
    'Ladder',
    'Drill',
    'Hand tools',
    'Wheelbarrow',
    'Trailer',
  ],
  'Labor': [
    'Moving',
    'Gardening',
    'Yard work',
    'Cleanup',
    'Heavy lifting',
  ],
  'Skills': [
    'Tutoring',
    'Tech support',
    'Carpentry',
    'Cooking',
    'Pet care',
  ],
};

List<String> get allPresetTags =>
    kTagPresets.values.expand((e) => e).toList(growable: false);
