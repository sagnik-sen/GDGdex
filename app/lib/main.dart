import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/admin.dart';
import 'screens/home.dart';
import 'screens/landing.dart';
import 'screens/leaderboard.dart';
import 'screens/login.dart';
import 'ui.dart';

void main() => runApp(const GdgDexApp());

class GdgDexApp extends StatelessWidget {
  const GdgDexApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GDGdex',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    onGenerateRoute: (s) => MaterialPageRoute(
      settings: s,
      builder: (_) => switch (s.name) {
        '/dex' => const AuthGate(child: HomeShell(tab: 0)),
        '/collection' => const AuthGate(child: HomeShell(tab: 1)),
        '/rank' => const AuthGate(child: HomeShell(tab: 2)),
        '/leaderboard' => const LeaderboardScreen(),
        '/board' => const LeaderboardScreen(projector: true),
        '/admin' => const AuthGate(adminOnly: true, child: AdminScreen()),
        _ => const LandingScreen(),
      },
    ),
  );
}

/// Shows [child] when signed in, otherwise the login form. Session lives in an HttpOnly cookie,
/// so a page refresh just re-asks the server who we are.
class AuthGate extends StatefulWidget {
  final Widget child;
  final bool adminOnly;
  const AuthGate({super.key, required this.child, this.adminOnly = false});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<void> _check = _load();
  Future<void> _load() async {
    if (Api.me.value == null) await Api.refreshMe();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _check,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snap.hasError) {
        return Scaffold(body: ErrorRetry(snap.error!, () => setState(() => _check = _load())));
      }
      return ValueListenableBuilder(
        valueListenable: Api.me,
        builder: (context, me, _) {
          if (me == null) return const LoginScreen();
          if (widget.adminOnly && me['isAdmin'] != true) {
            return const Scaffold(body: Center(child: Text('Organizers only.')));
          }
          return widget.child;
        },
      );
    },
  );
}
