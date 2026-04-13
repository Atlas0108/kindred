import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/models/user_profile.dart';
import '../core/services/user_profile_service.dart';

/// Lets staff switch the Profile tab (and new posts/events) to an org they’re listed on.
class ViewAsController extends ChangeNotifier {
  ViewAsController(this._auth, this._profileService) {
    _authSub = _auth.authStateChanges().listen((_) => _restartOrgListener());
    _restartOrgListener();
  }

  final FirebaseAuth _auth;
  final UserProfileService _profileService;

  StreamSubscription<List<UserProfile>>? _orgSub;
  StreamSubscription<User?>? _authSub;

  List<UserProfile> _orgs = [];
  String? _actingOrgUid;

  /// Profile tab + “post as” identity when acting for an org.
  String get effectiveProfileUid => _actingOrgUid ?? _auth.currentUser?.uid ?? '';

  String? get actingOrganizationUid => _actingOrgUid;

  bool get isActingAsOrganization =>
      _actingOrgUid != null && _actingOrgUid != _auth.currentUser?.uid;

  List<UserProfile> get staffOrganizations => List.unmodifiable(_orgs);

  void _restartOrgListener() {
    _orgSub?.cancel();
    _actingOrgUid = null;
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.trim().isEmpty) {
      _orgs = [];
      notifyListeners();
      return;
    }
    _orgSub = _profileService.staffOrganizationsStreamForEmail(email).listen((orgs) {
      _orgs = orgs;
      if (_actingOrgUid != null && !_orgs.any((p) => p.uid == _actingOrgUid)) {
        _actingOrgUid = null;
      }
      notifyListeners();
    });
  }

  void setActingOrganizationUid(String? orgUid) {
    final authUid = _auth.currentUser?.uid;
    if (orgUid == null || orgUid.isEmpty || orgUid == authUid) {
      _actingOrgUid = null;
      notifyListeners();
      return;
    }
    if (!_orgs.any((p) => p.uid == orgUid)) return;
    _actingOrgUid = orgUid;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _orgSub?.cancel();
    super.dispose();
  }
}
