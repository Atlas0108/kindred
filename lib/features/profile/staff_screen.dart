import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/user_account_type.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/user_profile_service.dart';
import '../../widgets/close_to_shell.dart';

const _headerGreen = Color(0xFF2E7D5A);
const _pageBackground = Color(0xFFF9F7F2);

/// Manage [UserProfile.staffEmails] for the signed-in nonprofit/business account.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Sign in required.')));
    }
    final svc = context.read<UserProfileService>();
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        title: const Text('Staff'),
        backgroundColor: _pageBackground,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        actions: const [CloseToShellIconButton()],
      ),
      body: StreamBuilder<UserProfile?>(
        stream: svc.profileStream(user.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final p = snap.data;
          if (p == null) {
            return const Center(child: Text('Profile not found.'));
          }
          if (p.accountType != UserAccountType.nonprofit && p.accountType != UserAccountType.business) {
            return const Center(child: Text('Staff is only for nonprofit and business accounts.'));
          }
          final emails = p.staffEmails;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                'People you add can sign in with their own Kindred account and choose to view '
                'and post as ${p.publicDisplayLabel} from the menu at the top of the app.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _showAddStaffDialog(context),
                style: FilledButton.styleFrom(
                  backgroundColor: _headerGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add staff'),
              ),
              const SizedBox(height: 24),
              Text(
                'Staff emails',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (emails.isEmpty)
                Text(
                  'No staff yet.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                )
              else
                ...emails.map(
                  (e) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(e),
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle_outline, color: Theme.of(context).colorScheme.error),
                        onPressed: () => _confirmRemove(context, e),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showAddStaffDialog(BuildContext context) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add staff'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'colleague@example.com',
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
      final email = ctrl.text;
      try {
        await context.read<UserProfileService>().addStaffEmailToMyOrganization(email);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff added')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _confirmRemove(BuildContext context, String email) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove staff'),
        content: Text('Remove $email? They will no longer be able to view as this account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    try {
      await context.read<UserProfileService>().removeStaffEmailFromMyOrganization(email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
