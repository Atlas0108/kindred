import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/connection_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../widgets/connection_approve_decline_row.dart';

const _headerGreen = Color(0xFF2E7D5A);
const _slateSubtitle = Color(0xFF5B6B7A);

/// Matches [ProfileScreen] Message / Inbox primary buttons.
const _btnPadding = EdgeInsets.symmetric(vertical: 16);
const _btnShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
);

/// Connection actions when viewing someone else’s profile.
class ProfileConnectionButton extends StatefulWidget {
  const ProfileConnectionButton({
    super.key,
    required this.otherUid,
    required this.otherDisplayName,
  });

  final String otherUid;
  final String otherDisplayName;

  @override
  State<ProfileConnectionButton> createState() => _ProfileConnectionButtonState();
}

class _ProfileConnectionButtonState extends State<ProfileConnectionButton> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _connSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _outReqSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _inReqSub;

  bool _connExists = false;
  bool _outPending = false;
  bool _inPending = false;
  bool _ready = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == widget.otherUid) return;

    final fs = FirebaseFirestore.instance;
    _connSub = fs.collection('users').doc(me).collection('connections').doc(widget.otherUid).snapshots().listen(
      (s) {
        _connExists = s.exists;
        _bumpReady();
      },
    );
    _outReqSub =
        fs.collection('users').doc(widget.otherUid).collection('connectionRequests').doc(me).snapshots().listen(
      (s) {
        _outPending = s.exists;
        _bumpReady();
      },
    );
    _inReqSub = fs.collection('users').doc(me).collection('connectionRequests').doc(widget.otherUid).snapshots().listen(
      (s) {
        _inPending = s.exists;
        _bumpReady();
      },
    );
  }

  void _bumpReady() {
    if (!mounted) return;
    setState(() {
      _ready = true;
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _outReqSub?.cancel();
    _inReqSub?.cancel();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_busy) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final connectionSvc = context.read<ConnectionService>();
    final profileSvc = context.read<UserProfileService>();
    setState(() => _busy = true);
    try {
      final p = await profileSvc.fetchProfile(me.uid);
      final name = p?.displayName.trim().isNotEmpty == true
          ? p!.displayName
          : UserProfileService.preferredDisplayNameFromAuthUser(me);
      await connectionSvc.sendConnectionRequest(
            toUserId: widget.otherUid,
            myDisplayName: name,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection request sent')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send request: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    if (_busy) return;
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final connectionSvc = context.read<ConnectionService>();
    final profileSvc = context.read<UserProfileService>();
    setState(() => _busy = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(me.uid)
          .collection('connectionRequests')
          .doc(widget.otherUid)
          .get();
      final data = snap.data();
      final theirName = (data?['fromDisplayName'] as String?)?.trim().isNotEmpty == true
          ? data!['fromDisplayName'] as String
          : widget.otherDisplayName;

      final p = await profileSvc.fetchProfile(me.uid);
      final myName = p?.displayName.trim().isNotEmpty == true
          ? p!.displayName
          : UserProfileService.preferredDisplayNameFromAuthUser(me);

      await connectionSvc.approveConnectionRequest(
            fromUserId: widget.otherUid,
            fromDisplayName: theirName,
            myDisplayName: myName,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are now connected')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not approve: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    final connectionSvc = context.read<ConnectionService>();
    setState(() => _busy = true);
    try {
      await connectionSvc.declineConnectionRequest(widget.otherUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not decline: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRemoveConnection() async {
    if (_busy) return;
    final name = widget.otherDisplayName.trim().isEmpty ? 'this neighbor' : widget.otherDisplayName.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove connection?'),
        content: Text(
          'Remove your connection with $name? You can send a new request later if you change your mind.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final connectionSvc = context.read<ConnectionService>();
    setState(() => _busy = true);
    try {
      await connectionSvc.removeConnection(widget.otherUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove connection: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    if (_connExists) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _busy ? null : _confirmAndRemoveConnection,
          style: OutlinedButton.styleFrom(
            foregroundColor: errorColor,
            side: BorderSide(color: errorColor, width: 1.5),
            padding: _btnPadding,
            shape: _btnShape,
          ),
          child: _busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: errorColor,
                  ),
                )
              : const Text('Remove Connection'),
        ),
      );
    }

    if (_outPending) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _slateSubtitle,
            padding: _btnPadding,
            shape: _btnShape,
          ),
          child: const Text('Request sent'),
        ),
      );
    }

    if (_inPending) {
      return ConnectionApproveDeclineRow(
        busy: _busy,
        onDecline: _decline,
        onApprove: _approve,
      );
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _busy ? null : _sendRequest,
        style: OutlinedButton.styleFrom(
          foregroundColor: _headerGreen,
          side: const BorderSide(color: _headerGreen, width: 1.5),
          padding: _btnPadding,
          shape: _btnShape,
        ),
        child: _busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            : const Text('Request Connection'),
      ),
    );
  }
}
