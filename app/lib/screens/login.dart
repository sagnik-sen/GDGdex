import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _reg = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _reg.text.trim().isEmpty) {
      setState(() => _error = 'Enter your email and registration number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.login(_email.text, _reg.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Narrow(
          maxWidth: 420,
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              const SizedBox(height: 32),
              const Center(child: Wordmark(size: 36)),
              const SizedBox(height: 8),
              Text('Sign in to open your GDGdex', textAlign: TextAlign.center, style: t.bodyLarge),
              const SizedBox(height: 32),
              AutofillGroup(
                child: Column(
                  children: [
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reg,
                      obscureText: true,
                      textCapitalization: TextCapitalization.characters,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Registration number',
                        hintText: 'e.g. 23BCE1234',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: gRed, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('ENTER GDGDEX'),
              ),
              const SizedBox(height: 16),
              Text(
                'Trouble signing in? Find a GDG organizer.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
