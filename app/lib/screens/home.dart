import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../ui.dart';
import 'leaderboard.dart';
import 'scan.dart';

/// Signed-in shell: Dex card / Collection / Leaderboard, with SCAN always one tap away.
class HomeShell extends StatefulWidget {
  final int tab;
  const HomeShell({super.key, required this.tab});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.tab;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Picks up event start/end and count changes without a reload.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => Api.refreshMe().catchError((_) => null));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Api.me,
      builder: (context, me, _) {
        if (me == null) return const SizedBox();
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Wordmark(),
            actions: [
              Center(child: StatusPill(me['event']['status'])),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'admin') Navigator.pushNamed(context, '/admin');
                  if (v == 'board') Navigator.pushNamed(context, '/board');
                  if (v == 'logout') {
                    await Api.logout();
                  }
                },
                itemBuilder: (_) => [
                  if (me['isAdmin'] == true) const PopupMenuItem(value: 'admin', child: Text('Admin dashboard')),
                  const PopupMenuItem(value: 'board', child: Text('Projector leaderboard')),
                  const PopupMenuItem(value: 'logout', child: Text('Log out')),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              DexCardView(me: me),
              CollectionView(count: me['count']),
              LeaderboardView(active: _tab == 2),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: _tab == 0
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => startCollect(context, camera: true),
                  backgroundColor: gBlue,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('SCAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.badge_outlined),
                selectedIcon: Icon(Icons.badge),
                label: 'My Dex',
              ),
              NavigationDestination(
                icon: Badge.count(
                  count: me['count'],
                  isLabelVisible: me['count'] > 0,
                  child: const Icon(Icons.grid_view_outlined),
                ),
                selectedIcon: const Icon(Icons.grid_view_rounded),
                label: 'Collection',
              ),
              const NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard),
                label: 'Leaderboard',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- personal card

class DexCardView extends StatelessWidget {
  final Map<String, dynamic> me;
  const DexCardView({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final status = me['event']['status'];
    final int count = me['count'], total = me['total'];
    return RefreshIndicator(
      onRefresh: Api.refreshMe,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Narrow(
            maxWidth: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (status != 'ACTIVE') _Banner(status),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Pokédex-ish header strip
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: gRed,
                        child: Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFF8FD3FF),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'GDGDEX',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3),
                            ),
                            const Spacer(),
                            Text(
                              me['dexId'],
                              style: mono.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                        child: Column(
                          children: [
                            Avatar(me, size: 64),
                            const SizedBox(height: 12),
                            Text(
                              me['name'],
                              textAlign: TextAlign.center,
                              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            Text(me['role'], style: t.titleSmall?.copyWith(color: cs.outline)),
                            const SizedBox(height: 16),
                            GestureDetector(
                              onTap: () => _showBigQr(context, me),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                                child: QrImageView(data: me['qr'], size: 180, padding: EdgeInsets.zero),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('PASSKEY', style: t.labelSmall?.copyWith(letterSpacing: 2, color: cs.outline)),
                            SelectableText(
                              me['passkey'],
                              style: mono.copyWith(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 6),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        color: cs.surfaceContainerHigh,
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(
                                  'COLLECTED',
                                  style: t.labelMedium?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w700),
                                ),
                                const Spacer(),
                                Text(
                                  '$count',
                                  style: mono.copyWith(fontSize: 26, fontWeight: FontWeight.w900, color: gBlue),
                                ),
                                Text(' / $total', style: mono.copyWith(fontSize: 16, color: cs.outline)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: total == 0 ? 0 : count / total,
                                minHeight: 8,
                                color: gGreen,
                                backgroundColor: cs.surface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => startCollect(context, camera: true),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('SCAN GDGDEX'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 60), backgroundColor: gBlue),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => startCollect(context, camera: false),
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('ENTER PASSKEY'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBigQr(BuildContext context, Map<String, dynamic> me) => showDialog(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: me['qr'], size: 300, padding: EdgeInsets.zero),
            const SizedBox(height: 12),
            Text(
              me['passkey'],
              style: mono.copyWith(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8, color: Colors.black),
            ),
            Text(me['name'], style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ),
  );
}

class _Banner extends StatelessWidget {
  final String status;
  const _Banner(this.status);
  @override
  Widget build(BuildContext context) {
    final ended = status == 'ENDED';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (ended ? gRed : gYellow).withValues(alpha: .15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(ended ? Icons.flag : Icons.hourglass_top, color: ended ? gRed : gYellow),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ended
                  ? 'The event has ended. Check the leaderboard for final rankings!'
                  : "Collecting opens when the organizers start the event. Get your QR ready!",
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- collection

class CollectionView extends StatefulWidget {
  /// Changes whenever a new entry lands, which triggers a reload.
  final int count;
  const CollectionView({super.key, required this.count});
  @override
  State<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends State<CollectionView> {
  late Future<Json> _data = Api.get('collection');
  String _q = '';

  @override
  void didUpdateWidget(CollectionView old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _data = Api.get('collection');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) return ErrorRetry(snap.error!, () => setState(() => _data = Api.get('collection')));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = (snap.data!['entries'] as List).cast<Json>();
        final total = snap.data!['total'] as int;
        final q = _q.toLowerCase();
        final shown = all
            .where((m) => q.isEmpty || '${m['name']} ${m['role']} ${m['dexId']}'.toLowerCase().contains(q))
            .toList();
        return RefreshIndicator(
          onRefresh: () async {
            setState(() => _data = Api.get('collection'));
            await _data;
          },
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOUR GDGDEX', style: t.labelLarge?.copyWith(letterSpacing: 3, fontWeight: FontWeight.w800)),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${all.length}',
                              style: mono.copyWith(color: gBlue, fontWeight: FontWeight.w900),
                            ),
                            TextSpan(text: ' / $total discovered'),
                          ],
                        ),
                        style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : all.length / total,
                          minHeight: 6,
                          color: gGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (all.isNotEmpty)
                        TextField(
                          onChanged: (v) => setState(() => _q = v),
                          decoration: const InputDecoration(
                            hintText: 'Search your GDGdex',
                            prefixIcon: Icon(Icons.search),
                            isDense: true,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (all.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.travel_explore, size: 56),
                        SizedBox(height: 12),
                        Text('No entries yet.\nGo meet someone and scan their GDGdex!', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: .8,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => EntryCard(shown[i], onTap: () => showEntry(context, shown[i])),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
