import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/models/connection_request.dart';
import '../../core/models/user_connection.dart';
import '../../core/services/connection_service.dart';
import '../../core/services/user_profile_service.dart';
import '../../widgets/connection_approve_decline_row.dart';
import '../../widgets/pending_connection_requests_badge.dart';

const _requestsTabIndex = 1;

/// Tabbed view of accepted connections and incoming requests.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return const Scaffold(body: Center(child: Text('Sign in to view connections.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: 'My connections'),
            Tab(
              child: AnimatedBuilder(
                animation: _tabs,
                builder: (context, _) {
                  final svc = context.read<ConnectionService>();
                  return StreamBuilder<int>(
                    stream: svc.incomingRequestCountStream(),
                    builder: (context, snap) {
                      final pending = snap.data ?? 0;
                      final showBadge =
                          pending > 0 && _tabs.index != _requestsTabIndex;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('Requests'),
                          if (showBadge) ...[
                            const SizedBox(width: 6),
                            PendingConnectionRequestsBadge(count: pending),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ConnectionsList(onOpenProfile: (uid) => context.push('/u/$uid')),
          _RequestsList(
            onApproved: () {
              if (_tabs.index == 1) {
                _tabs.animateTo(0);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ConnectionsList extends StatelessWidget {
  const _ConnectionsList({required this.onOpenProfile});

  final void Function(String uid) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ConnectionService>();
    final dateFmt = DateFormat.yMMMd();

    return StreamBuilder<List<UserConnection>>(
      stream: svc.myConnectionsStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load connections.\n${snap.error}', textAlign: TextAlign.center),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'No connections yet.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final c = list[i];
            final initial =
                c.peerDisplayName.trim().isEmpty ? '?' : c.peerDisplayName.trim().substring(0, 1).toUpperCase();
            return ListTile(
              leading: CircleAvatar(child: Text(initial)),
              title: Text(c.peerDisplayName),
              subtitle: Text('Since ${dateFmt.format(c.connectedAt.toLocal())}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenProfile(c.peerId),
            );
          },
        );
      },
    );
  }
}

class _RequestsList extends StatelessWidget {
  const _RequestsList({required this.onApproved});

  final VoidCallback onApproved;

  @override
  Widget build(BuildContext context) {
    final svc = context.read<ConnectionService>();
    final theme = Theme.of(context);
    final dateFmt = DateFormat.MMMd();
    final timeFmt = DateFormat.jm();

    return StreamBuilder<List<ConnectionRequest>>(
      stream: svc.incomingRequestsStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load requests.\n${snap.error}', textAlign: TextAlign.center),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'No pending requests.',
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final r = list[i];
            final t = r.createdAt.toLocal();
            final sub = DateTime.now().difference(t).inHours < 24 ? timeFmt.format(t) : dateFmt.format(t);
            final initial = r.fromDisplayName.trim().isEmpty
                ? '?'
                : r.fromDisplayName.trim().substring(0, 1).toUpperCase();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => context.push('/u/${r.fromUserId}'),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                          child: Row(
                            children: [
                              CircleAvatar(child: Text(initial)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.fromDisplayName,
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      sub,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: ConnectionApproveDeclineRow(
                        onDecline: () => _decline(context, svc, r.fromUserId),
                        onApprove: () => _approve(context, svc, r, onApproved),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _approve(
    BuildContext context,
    ConnectionService svc,
    ConnectionRequest r,
    VoidCallback onApproved,
  ) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    try {
      final profileSvc = context.read<UserProfileService>();
      final p = await profileSvc.fetchProfile(me.uid);
      final myName = p?.publicDisplayLabel.trim().isNotEmpty == true &&
              p!.publicDisplayLabel != 'Neighbor'
          ? p.publicDisplayLabel
          : UserProfileService.preferredDisplayNameFromAuthUser(me);

      await svc.approveConnectionRequest(
        fromUserId: r.fromUserId,
        fromDisplayName: r.fromDisplayName,
        myDisplayName: myName,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection approved')),
        );
        onApproved();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not approve: $e')),
        );
      }
    }
  }

  static Future<void> _decline(BuildContext context, ConnectionService svc, String fromUserId) async {
    try {
      await svc.declineConnectionRequest(fromUserId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not decline: $e')),
        );
      }
    }
  }
}
