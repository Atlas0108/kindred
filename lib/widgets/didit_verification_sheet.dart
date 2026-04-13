import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/didit/kindred_didit_result.dart';
import '../core/didit/kindred_didit_verification.dart';

const _docFlutterSdk = 'https://docs.didit.me/integration/native-sdks/flutter-sdk';
const _docWebhooks = 'https://docs.didit.me/integration/webhooks';
const _docSessionsApi = 'https://docs.didit.me/sessions-api/create-session';

/// Opens the Didit integration sheet (v3 session + webhook + Flutter SDK).
Future<void> showDiditVerificationSheet(
  BuildContext context, {
  required String vendorData,
  String? subjectDisplayName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => DiditVerificationSheet(
      vendorData: vendorData,
      subjectDisplayName: subjectDisplayName,
    ),
  );
}

class DiditVerificationSheet extends StatefulWidget {
  const DiditVerificationSheet({
    super.key,
    required this.vendorData,
    this.subjectDisplayName,
  });

  final String vendorData;
  final String? subjectDisplayName;

  @override
  State<DiditVerificationSheet> createState() => _DiditVerificationSheetState();
}

class _DiditVerificationSheetState extends State<DiditVerificationSheet> {
  bool _launching = false;
  /// JPEG bytes for Didit `portrait_image` (biometric / face-match workflows).
  Uint8List? _portraitJpeg;

  Future<void> _pickPortrait() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 88,
    );
    if (file == null || !mounted) return;
    final raw = await file.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that image.')),
      );
      return;
    }

    const maxSide = 720;
    img.Image resized = decoded;
    if (decoded.width > maxSide || decoded.height > maxSide) {
      if (decoded.width >= decoded.height) {
        resized = img.copyResize(decoded, width: maxSide);
      } else {
        resized = img.copyResize(decoded, height: maxSide);
      }
    }

    var quality = 85;
    var jpg = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    while (jpg.length > 950000 && quality > 45) {
      quality -= 8;
      jpg = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    }

    if (!mounted) return;
    setState(() => _portraitJpeg = jpg);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _startNativeFlow() async {
    final workflowId = dotenv.env['DIDIT_WORKFLOW_ID']?.trim();
    if (workflowId == null || workflowId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set DIDIT_WORKFLOW_ID in .env for the in-app SDK (Unilink flow).'),
        ),
      );
      return;
    }

    setState(() => _launching = true);
    final result = await kindredLaunchDiditVerification(
      workflowId: workflowId,
      vendorData: widget.vendorData,
      callbackUrl: kIsWeb ? Uri.base.origin : null,
      portraitImageBase64:
          kIsWeb && _portraitJpeg != null ? base64Encode(_portraitJpeg!) : null,
    );
    if (!mounted) return;
    setState(() => _launching = false);

    switch (result) {
      case KindredDiditSdkCompleted(:final statusLabel, :final sessionId):
        final sid = sessionId != null ? ' Session: $sessionId.' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Didit: $statusLabel.$sid Your backend webhook should confirm the final outcome.',
            ),
          ),
        );
      case KindredDiditSdkCancelled():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification cancelled.')),
        );
      case KindredDiditSdkFailed(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      case KindredDiditUnsupported(:final reason):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appId = dotenv.env['DIDIT_APP_ID']?.trim();
    final workflowConfigured = (dotenv.env['DIDIT_WORKFLOW_ID']?.trim().isNotEmpty ?? false);
    final codeStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.35,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verify with Didit',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              widget.subjectDisplayName != null
                  ? 'Identity verification for ${widget.subjectDisplayName}. '
                      'Use the steps below to wire Didit on your server and in the mobile app.'
                  : 'Use the steps below to wire Didit. Open Developer details to copy the profile id '
                      'your backend should send as vendor_data.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                expandedAlignment: Alignment.centerLeft,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  'Developer details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  if (appId != null && appId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SelectableText(
                        'Didit app id: $appId',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Text(
                    'Profile id (use as vendor_data)',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          widget.vendorData,
                          style: codeStyle,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy profile id',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.vendorData));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Profile id copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionTitle(theme, '1. Create sessions (v3 API)'),
            const SizedBox(height: 6),
            Text(
              kIsWeb
                  ? 'This web app calls the Firebase callable createDiditSession (us-central1), which POSTs to Didit using a server-side secret. Your own backend can call Didit the same way:'
                  : 'From a trusted server (never ship your API key in the client), call:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              'POST https://verification.didit.me/v3/session/\n'
              'Headers:\n'
              '  x-api-key: <DIDIT_API_KEY>\n'
              '  Content-Type: application/json\n'
              'Body (example):\n'
              '{\n'
              '  "workflow_id": "<your_workflow_id>",\n'
              '  "vendor_data": "${widget.vendorData}"\n'
              '}',
              style: codeStyle,
            ),
            const SizedBox(height: 8),
            Text(
              'Response includes url (open in browser on web), session_token (native SDK), and session_id.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openUrl(_docSessionsApi),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Create session API docs'),
            ),
            const SizedBox(height: 16),
            _sectionTitle(theme, '2. Webhooks (v3)'),
            const SizedBox(height: 6),
            Text(
              'In Didit Console → API & Webhooks, set your HTTPS endpoint and copy the webhook secret. '
              'Verify incoming POST bodies with the signature headers (prefer X-Signature-V2). '
              'Return 200 quickly; persist verification status against vendor_data / session_id.',
              style: theme.textTheme.bodyMedium,
            ),
            TextButton.icon(
              onPressed: () => _openUrl(_docWebhooks),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Webhook & signature docs'),
            ),
            const SizedBox(height: 16),
            _sectionTitle(theme, '3. Flutter SDK (didit_sdk)'),
            const SizedBox(height: 6),
            Text(
              'Production: pass session_token from your backend into the SDK.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              "import 'package:didit_sdk/sdk_flutter.dart';\n\n"
              '// Recommended (session from your backend):\n'
              'final result = await DiditSdk.startVerification(sessionToken);\n\n'
              '// Unilink (workflow id in .env). vendorData must match POST /v3/session/ vendor_data:\n'
              'final result = await DiditSdk.startVerificationWithWorkflow(\n'
              '  workflowId,\n'
              '  vendorData: profileUid, // route param or value from Developer details → Copy\n'
              ');',
              style: codeStyle,
            ),
            const SizedBox(height: 6),
            Text(
              'Use the same vendor_data string in your server session and in this call.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'iOS: add the DiditSDK podspec to your Podfile. Android: add packaging pickFirst for BouncyCastle META-INF (see pub.dev/didit_sdk). '
              'Web: deploy functions/createDiditSession and set secret DIDIT_API_KEY; Start verification uses the callable then opens url.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextButton.icon(
              onPressed: () => _openUrl(_docFlutterSdk),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Flutter SDK docs'),
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 20),
              _sectionTitle(theme, 'Reference selfie (biometric workflows)'),
              const SizedBox(height: 6),
              Text(
                'If your Didit workflow uses face match / biometric auth, the API requires a '
                'portrait_image when creating the session. Add a clear photo of the person’s face.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickPortrait,
                icon: const Icon(Icons.face, size: 20),
                label: Text(_portraitJpeg == null ? 'Choose portrait photo' : 'Replace portrait photo'),
              ),
              if (_portraitJpeg != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _portraitJpeg!,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _launching ? null : _startNativeFlow,
              child: _launching
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      workflowConfigured
                          ? (kIsWeb
                              ? 'Start verification'
                              : 'Start verification (native SDK)')
                          : 'Start verification (set DIDIT_WORKFLOW_ID first)',
                    ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}
