import 'package:flutter/material.dart';

/// Kindred green; matches profile primary actions.
const _headerGreen = Color(0xFF2E7D5A);

const _actionPadding = EdgeInsets.symmetric(vertical: 16);
const _actionShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
);

/// Decline (outlined, left) · Approve (filled green, right) — same everywhere.
class ConnectionApproveDeclineRow extends StatelessWidget {
  const ConnectionApproveDeclineRow({
    super.key,
    required this.onDecline,
    required this.onApprove,
    this.busy = false,
  });

  final VoidCallback? onDecline;
  final VoidCallback? onApprove;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onDecline,
            style: OutlinedButton.styleFrom(
              padding: _actionPadding,
              shape: _actionShape,
            ),
            child: const Text('Decline'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : onApprove,
            style: FilledButton.styleFrom(
              backgroundColor: _headerGreen,
              foregroundColor: Colors.white,
              padding: _actionPadding,
              shape: _actionShape,
            ),
            child: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Approve'),
          ),
        ),
      ],
    );
  }
}
