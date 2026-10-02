import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../ui.dart';

const _medals = [Color(0xFFFFC83D), Color(0xFFC0C7D1), Color(0xFFD08A4E)];

/// Standalone public leaderboard route (`/leaderboard`, or `/board` for the projector).
class LeaderboardScreen extends StatelessWidget {
  final bool projector;
  const LeaderboardScreen({super.key, this.projector = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: projector ? null : AppBar(title: const Wordmark()),
    body: SafeArea(child: LeaderboardView(projector: projector)),
  );
}

/// Polls the server; freezes naturally once the event is ENDED (no new collections are accepted).
class LeaderboardView extends StatefulWidget {
  final bool projector;

  /// Only poll while on screen; the tab stays alive in an IndexedStack.
  final bool active;
  const LeaderboardView({super.key, this.projector = false, this.active = true});
  @override
  State<LeaderboardView> createState() => _LeaderboardViewState();
}

class _LeaderboardViewState extends State<LeaderboardView> {
  Json? _data;
  Json? _stats;
  List<Json> _recent = [];
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(LeaderboardView old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    _timer?.cancel();
    if (widget.active) _start();
  }

  void _start() {
    _load();
    _timer = Timer.periodic(Duration(seconds: widget.projector ? 4 : 8), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final d = await Api.get('leaderboard');
      final s = widget.projector ? await Api.get('state') : null;
      if (mounted) {
        setState(() {
          _data = d;
          _stats = s?['stats'] as Json?;
          _recent = ((s?['recent'] as List?) ?? []).cast<Json>();
          _error = null;
        });
      }
    } catch (e) {
      // Keep showing the last good board on a blip; only surface errors if we have nothing.
      if (mounted && _data == null) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return _error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator());
    }
    final status = _data!['event']['status'] as String;
    final entries = (_data!['entries'] as List).cast<Json>();
    final ended = status == 'ENDED';
    final p = widget.projector;
    final scale = p ? 1.6 : 1.0;
    final t = Theme.of(context).textTheme;
    final myId = Api.me.value?['dexId'];
    final top = entries.take(3).where((e) => e['count'] > 0).toList();
    final rest = entries.skip(top.length).take(p ? 7 : 1000).toList();

    final board = ListView(
      padding: EdgeInsets.fromLTRB(16, p ? 24 : 4, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                ended ? 'FINAL RANKINGS' : 'GDGDEX LEADERBOARD',
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 22 * scale),
              ),
            ),
            StatusPill(status),
          ],
        ),
        const SizedBox(height: 12),
        if (ended && top.isNotEmpty) _Winner(top.first, scale),
        if (top.isNotEmpty) _Podium(top, scale: scale, myId: myId),
        if (entries.every((e) => e['count'] == 0))
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              status == 'NOT_STARTED' ? 'The hunt begins soon.' : 'No entries yet — be the first!',
              textAlign: TextAlign.center,
              style: t.titleMedium,
            ),
          ),
        for (final e in rest) _Row(e, scale: scale, me: e['dexId'] == myId),
        if (ended) ...[
          const SizedBox(height: 12),
          Text(
            'Ties are broken by whoever reached their count first.',
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ],
    );

    if (!p) {
      return RefreshIndicator(
        onRefresh: _load,
        child: Narrow(maxWidth: 640, child: board),
      );
    }

    // Projector: board + live discovery feed + side panel with stats and a join QR.
    return Row(
      children: [
        Expanded(flex: 3, child: board),
        SizedBox(width: 400, child: _Feed(_recent)),
        Container(
          width: 360,
          padding: const EdgeInsets.all(32),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Wordmark(size: 40),
              const SizedBox(height: 4),
              Text('Gotta GDG ’em all.', style: t.titleMedium),
              const SizedBox(height: 32),
              if (_stats != null) ...[
                _BigStat('${_stats!['members']}', 'participants'),
                _BigStat('${_stats!['collections']}', 'entries discovered'),
              ],
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: Uri.base.origin, size: 180, padding: EdgeInsets.zero),
              ),
              const SizedBox(height: 8),
              Text(Uri.base.host, style: mono.copyWith(fontSize: 16)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ticker of the latest discoveries; new rows slide in.
class _Feed extends StatelessWidget {
  final List<Json> items;
  const _Feed(this.items);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 24, 16, 24),
      children: [
        Text(
          'LIVE DISCOVERIES',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 20, color: cs.outline),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty) Text('Waiting for the first catch…', style: TextStyle(color: cs.outline, fontSize: 18)),
        for (final e in items)
          TweenAnimationBuilder<double>(
            key: ValueKey('${e['at']}${e['collector']}${e['dexId']}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(40 * (1 - v), 0), child: child),
            ),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border(left: BorderSide(color: colorFor(e['dexId']), width: 4)),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: e['collector'],
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(
                      text: ' discovered ',
                      style: TextStyle(color: cs.outline),
                    ),
                    TextSpan(
                      text: e['collected'],
                      style: TextStyle(fontWeight: FontWeight.w800, color: colorFor(e['dexId'])),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
      ],
    );
  }
}

class _BigStat extends StatelessWidget {
  final String value, label;
  const _BigStat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      children: [
        Text(
          value,
          style: mono.copyWith(fontSize: 48, fontWeight: FontWeight.w900, color: gBlue),
        ),
        Text(label.toUpperCase(), style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _Winner extends StatelessWidget {
  final Json e;
  final double scale;
  const _Winner(this.e, this.scale);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: EdgeInsets.all(16 * scale),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [gBlue, gGreen]),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Text('🏆', style: TextStyle(fontSize: 40 * scale)),
        SizedBox(width: 12 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WINNER',
                style: TextStyle(
                  color: Colors.white70,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w800,
                  fontSize: 12 * scale,
                ),
              ),
              Text(
                e['name'],
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24 * scale),
              ),
              Text(
                '${e['count']} discovered',
                style: TextStyle(color: Colors.white, fontSize: 14 * scale),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Podium extends StatelessWidget {
  final List<Json> top;
  final double scale;
  final String? myId;
  const _Podium(this.top, {required this.scale, this.myId});

  @override
  Widget build(BuildContext context) {
    // Display order 2-1-3 so first place sits in the middle.
    final order = [if (top.length > 1) 1, 0, if (top.length > 2) 2];
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: top.length == 1 ? 80.0 * scale : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in order)
            Expanded(
              child: Column(
                children: [
                  Avatar(top[i], size: (i == 0 ? 84 : 64) * scale),
                  const SizedBox(height: 6),
                  Text(
                    top[i]['name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14 * scale,
                      color: top[i]['dexId'] == myId ? gBlue : null,
                    ),
                  ),
                  Text(
                    '${top[i]['count']}',
                    style: mono.copyWith(fontWeight: FontWeight.w900, fontSize: 22 * scale),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: [110.0, 80.0, 60.0][i] * scale,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: _medals[i].withValues(alpha: .25),
                      border: Border(top: BorderSide(color: _medals[i], width: 4)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(fontSize: 32 * scale, fontWeight: FontWeight.w900, color: _medals[i]),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Json e;
  final double scale;
  final bool me;
  const _Row(this.e, {required this.scale, required this.me});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: me ? gBlue.withValues(alpha: .15) : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: me ? Border.all(color: gBlue) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40 * scale,
            child: Text(
              '${e['rank']}',
              style: mono.copyWith(fontWeight: FontWeight.w900, fontSize: 18 * scale, color: cs.outline),
            ),
          ),
          Avatar(e, size: 40 * scale),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me ? '${e['name']} (you)' : e['name'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15 * scale),
                ),
                Text(
                  e['role'] ?? '',
                  maxLines: 1,
                  style: TextStyle(color: cs.outline, fontSize: 12 * scale),
                ),
              ],
            ),
          ),
          Text(
            '${e['count']}',
            style: mono.copyWith(fontWeight: FontWeight.w900, fontSize: 22 * scale),
          ),
        ],
      ),
    );
  }
}
