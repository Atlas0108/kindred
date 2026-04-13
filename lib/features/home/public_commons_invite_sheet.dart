import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../core/services/public_commons_invite_service.dart';

/// Bottom sheet: enter an email and send a Public Commons join invite.
Future<void> showPublicCommonsInviteSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _PublicCommonsInviteSheetBody(),
  );
}

class _PublicCommonsInviteSheetBody extends StatefulWidget {
  const _PublicCommonsInviteSheetBody();

  @override
  State<_PublicCommonsInviteSheetBody> createState() => _PublicCommonsInviteSheetBodyState();
}

class _PublicCommonsInviteSheetBodyState extends State<_PublicCommonsInviteSheetBody> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() {
      _error = null;
      _sending = true;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await sendPublicCommonsInviteEmail(_email.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Invite sent.')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? e.code;
          _sending = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Invite someone',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'We’ll email them a link to join Public Commons.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              hintText: 'neighbor@example.com',
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onSubmitted: _sending ? null : (_) => _submit(),
            enabled: !_sending,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _sending ? null : _submit,
            child: _sending
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onPrimary,
                    ),
                  )
                : const Text('Send invite'),
          ),
        ],
      ),
    );
  }
}
