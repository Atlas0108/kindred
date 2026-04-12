import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Post tab: choose post type, then open the right composer.
class PostHubScreen extends StatelessWidget {
  const PostHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'What would you like to share?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Events go on the calendar; offers and requests are help-desk posts.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              _PostTypeCard(
                icon: Icons.event_available_outlined,
                iconColor: scheme.primary,
                title: 'Event',
                subtitle:
                    'Title, organizer, description, categories, schedule, and location or meeting link.',
                onTap: () => context.push('/post/new/event'),
              ),
              const SizedBox(height: 12),
              _PostTypeCard(
                icon: Icons.handshake_outlined,
                iconColor: Colors.green.shade700,
                title: 'Offering help',
                subtitle: 'Something you can do or lend to neighbors.',
                onTap: () => context.push('/compose?kind=offer'),
              ),
              const SizedBox(height: 12),
              _PostTypeCard(
                icon: Icons.support_agent_outlined,
                iconColor: Colors.blue.shade700,
                title: 'Requesting help',
                subtitle: 'Ask for a hand, tools, or local knowledge.',
                onTap: () => context.push('/compose?kind=request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostTypeCard extends StatelessWidget {
  const _PostTypeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: iconColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
