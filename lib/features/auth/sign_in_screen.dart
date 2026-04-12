import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/kindred_trace.dart';
import '../../core/models/user_account_type.dart';
import '../../core/services/user_profile_service.dart';

String _formatAuthError(FirebaseAuthException e) {
  final code = e.code;
  final msg = (e.message ?? '').trim();
  final hint = switch (code) {
    'operation-not-allowed' =>
      'Enable Email/Password: Firebase Console → Authentication → Sign-in method.',
    'invalid-credential' || 'wrong-password' || 'user-not-found' =>
      'Check email and password, or register a new account.',
    'invalid-email' => 'That email address looks invalid.',
    'email-already-in-use' => 'An account already exists for this email — try Sign in.',
    'weak-password' => 'Password is too weak (use at least 6 characters).',
    'too-many-requests' => 'Too many attempts. Wait a bit and try again.',
    'network-request-failed' => 'Network error — check your connection.',
    'configuration-not-found' =>
      'Auth isn’t fully enabled for this Firebase project, or the Web API key is wrong.\n'
      '• Firebase Console → Build → Authentication → open it once (Get started).\n'
      '• Sign-in method → enable Email/Password.\n'
      '• Google Cloud Console → APIs & Library → enable “Identity Toolkit API”.\n'
      '• Cloud Console → APIs & Services → Credentials → your **browser** API key '
      '(same as firebase_options.dart): under API restrictions, allow Identity Toolkit API '
      '(or use “Don’t restrict” for a prototype). If the key is restricted to Maps only, '
      'sign-in will fail.',
    _ => null,
  };
  final core = msg.isNotEmpty ? '$code: $msg' : code;
  if (hint != null) {
    return '$core\n$hint';
  }
  return core;
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;
  UserAccountType _accountType = UserAccountType.personal;

  @override
  void initState() {
    super.initState();
    _applyDevPrefills();
  }

  void _applyDevPrefills() {
    if (!dotenv.isInitialized) return;
    final email = dotenv.maybeGet('KINDRED_DEV_EMAIL')?.trim();
    final password = dotenv.maybeGet('KINDRED_DEV_PASSWORD')?.trim();
    if (email != null && email.isNotEmpty) {
      _email.text = email;
    }
    if (password != null && password.isNotEmpty) {
      _password.text = password;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    kindredTrace('SignIn._submit start', 'register=$_register');
    setState(() {
      _busy = true;
      _error = null;
    });
    final userProfileService = context.read<UserProfileService>();
    var didRequestNavigation = false;
    try {
      final auth = FirebaseAuth.instance;
      if (_register) {
        kindredTrace('SignIn._submit createUserWithEmailAndPassword...');
        await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        kindredTrace('SignIn._submit createUser OK');
        if (!mounted) return;
      } else {
        kindredTrace('SignIn._submit signInWithEmailAndPassword...');
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        kindredTrace('SignIn._submit signIn OK');
        if (!mounted) return;
      }

      final u = auth.currentUser;
      if (u == null) {
        kindredTrace('SignIn._submit no currentUser');
        setState(() => _error = 'Signed in but no user — try again.');
        return;
      }

      kindredTrace('SignIn._submit currentUser', u.uid);

      if (_register) {
        kindredTrace('SignIn._submit ensureProfile (register)', _accountType.firestoreValue);
        try {
          await userProfileService.ensureProfile(
            displayName: 'Neighbor',
            accountType: _accountType,
          );
        } catch (e, st) {
          kindredTrace('SignIn._submit ensureProfile catch (ignored)', e);
          assert(() {
            kindredTrace('SignIn._submit ensureProfile stack', st);
            return true;
          }());
        }
        if (!mounted) return;
      } else {
        unawaited(() async {
          try {
            await userProfileService.ensureProfile(displayName: 'Neighbor');
          } catch (e, st) {
            kindredTrace('SignIn._ensureProfile catch (ignored)', e);
            assert(() {
              kindredTrace('SignIn._ensureProfile stack', st);
              return true;
            }());
          }
        }());
      }

      didRequestNavigation = true;
      kindredTrace('SignIn._submit context.go(/home)');
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      kindredTrace('SignIn._submit FirebaseAuthException', e.code);
      setState(() => _error = _formatAuthError(e));
    } catch (e, st) {
      kindredTrace('SignIn._submit catch', e);
      assert(() {
        kindredTrace('SignIn._submit stack', st);
        return true;
      }());
      setState(() => _error = '$e');
    } finally {
      kindredTrace('SignIn._submit finally', 'didRequestNavigation=$didRequestNavigation');
      if (mounted && !didRequestNavigation) {
        setState(() => _busy = false);
      }
    }
  }

  static String _accountTypeLabel(UserAccountType t) {
    return switch (t) {
      UserAccountType.personal => 'Personal',
      UserAccountType.nonprofit => 'Nonprofit',
      UserAccountType.business => 'Business',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Kindred', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      _register ? 'Create an account' : 'Sign in',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _busy ? null : _submit(),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Account type',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Neighbors see this on your profile.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...UserAccountType.values.map((t) {
                        final selected = _accountType == t;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: selected
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _busy ? null : () => setState(() => _accountType = t),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                child: Row(
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      size: 22,
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _accountTypeLabel(t),
                                        style: theme.textTheme.titleSmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_register ? 'Register' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                                _accountType = UserAccountType.personal;
                              }),
                      child: Text(_register ? 'Have an account? Sign in' : 'Need an account? Register'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
