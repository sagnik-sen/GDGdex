import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../api.dart';
import '../ui.dart';
import 'scan.dart' show showEntry;

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  Json? _stats;
  List<Json>? _members;
  Object? _error;
  String _q = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.get('admin/stats'), Api.get('admin/members')]);
      if (mounted) {
        setState(() {
          _stats = r[0];
          _members = (r[1]['members'] as List).cast<Json>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (ok != null && mounted) toast(context, ok);
      await _load();
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _setEvent(String status, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label?'),
        content: Text(switch (status) {
          'ACTIVE' => 'Participants will be able to collect entries immediately.',
          'ENDED' => 'New collections will be rejected and the leaderboard becomes final. All data is kept.',
          _ => 'Moves the event back to NOT STARTED. Existing collections are kept.',
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(label.toUpperCase())),
        ],
      ),
    );
    if (ok == true) await _run(() => Api.post('admin/event', {'status': status}), 'Event is now $status');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizer dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Projector view',
            onPressed: () => Navigator.pushNamed(context, '/board'),
            icon: const Icon(Icons.tv),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
            // Same-origin navigation carries the session cookie; the server replies with an attachment.
            onSelected: (f) => web.window.open('/api/admin/export/$f', '_blank'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'members.csv', child: Text('Members + counts (CSV)')),
              PopupMenuItem(value: 'collections.csv', child: Text('All collections (CSV)')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMember(null),
        icon: const Icon(Icons.person_add),
        label: const Text('Add member'),
      ),
      body: _members == null
          ? (_error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: Narrow(
                maxWidth: 900,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    _eventCard(t),
                    const SizedBox(height: 12),
                    _statsGrid(),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          'MEMBERS (${_members!.length})',
                          style: t.labelLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => setState(() => _q = v.toLowerCase()),
                      decoration: const InputDecoration(
                        hintText: 'Search name, email, role, GDG-###',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final m in _members!.where(
                      (m) =>
                          _q.isEmpty ||
                          '${m['name']} ${m['email']} ${m['role']} ${m['dexId']}'.toLowerCase().contains(_q),
                    ))
                      _memberTile(m),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _eventCard(TextTheme t) {
    final e = _stats!['event'] as Json;
    final status = e['status'] as String;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('EVENT', style: t.labelLarge?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800)),
                const SizedBox(width: 12),
                StatusPill(status),
              ],
            ),
            if (e['startedAt'] != null)
              Text('Started ${_fmt(e['startedAt'])}${e['endedAt'] != null ? ' · Ended ${_fmt(e['endedAt'])}' : ''}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status != 'ACTIVE')
                  FilledButton.icon(
                    onPressed: () => _setEvent('ACTIVE', status == 'ENDED' ? 'Reopen event' : 'Start event'),
                    style: FilledButton.styleFrom(backgroundColor: gGreen),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(status == 'ENDED' ? 'REOPEN' : 'START EVENT'),
                  ),
                if (status == 'ACTIVE')
                  FilledButton.icon(
                    onPressed: () => _setEvent('ENDED', 'End event'),
                    style: FilledButton.styleFrom(backgroundColor: gRed),
                    icon: const Icon(Icons.stop),
                    label: const Text('END EVENT'),
                  ),
                if (status != 'NOT_STARTED')
                  OutlinedButton(
                    onPressed: () => _setEvent('NOT_STARTED', 'Reset to not started'),
                    child: const Text('RESET STATUS'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsGrid() {
    final s = _stats!['stats'] as Json;
    final most = s['mostCollected'] as Json?;
    final top = s['topCollector'] as Json?;
    final tiles = [
      ('Members', '${s['members']}', null),
      ('Total collections', '${s['collections']}', null),
      ('Unique discovered', '${s['uniqueDiscovered']}', null),
      ('Most collected', most == null ? '—' : '${most['count']}', most?['name']),
      ('Highest count', top == null ? '—' : '${top['count']}', top?['name']),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 700 ? 5 : 2;
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value, sub) in tiles)
              SizedBox(
                width: w,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: Theme.of(context).textTheme.labelSmall),
                        Text(
                          value,
                          style: mono.copyWith(fontSize: 26, fontWeight: FontWeight.w900, color: gBlue),
                        ),
                        Text(
                          sub ?? ' ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _memberTile(Json m) {
    final active = m['isActive'] == true;
    return Opacity(
      opacity: active ? 1 : .5,
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          leading: Avatar(m, size: 40),
          title: Text(
            '${m['name']}${m['isAdmin'] == true ? '  ·  admin' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${m['dexId']} · ${m['role']} · ${m['email']}${active ? '' : ' · DISABLED'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('${m['count']}', style: mono.copyWith(fontSize: 20, fontWeight: FontWeight.w900)),
          onTap: () => _profile(m),
        ),
      ),
    );
  }

  Future<void> _profile(Json m) async {
    await showDialog(
      context: context,
      builder: (ctx) => FutureBuilder(
        future: Api.get('admin/members/${m['dexId']}'),
        builder: (ctx, snap) {
          final d = snap.data;
          final mem = (d?['member'] as Json?) ?? m;
          final col = ((d?['collection'] as List?) ?? []).cast<Json>();
          return AlertDialog(
            title: Row(
              children: [
                Avatar(mem, size: 44),
                const SizedBox(width: 12),
                Expanded(child: Text(mem['name'])),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text('${mem['dexId']} · ${mem['role']}'),
                  Text(mem['email']),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Passkey: '),
                      SelectableText(
                        mem['passkey'],
                        style: mono.copyWith(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 3),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Collected ${mem['count']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Divider(),
                  if (!snap.hasData) const LinearProgressIndicator(),
                  for (final e in col)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(e, size: 28),
                      title: Text(e['name']),
                      trailing: Text(e['dexId'], style: mono),
                      onTap: () => showEntry(ctx, e),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _editMember(mem);
                },
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: ctx,
                    builder: (c) => AlertDialog(
                      title: const Text('Regenerate passkey?'),
                      content: const Text('Their old QR code and passkey will stop working immediately.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('REGENERATE')),
                      ],
                    ),
                  );
                  if (ok == true && ctx.mounted) {
                    Navigator.pop(ctx);
                    await _run(() => Api.post('admin/members/${mem['dexId']}/passkey'), 'New passkey generated');
                  }
                },
                child: const Text('New passkey'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _run(
                    () => Api.patch('admin/members/${mem['dexId']}', {'isActive': !(mem['isActive'] == true)}),
                    mem['isActive'] == true ? 'Member disabled' : 'Member enabled',
                  );
                },
                style: TextButton.styleFrom(foregroundColor: mem['isActive'] == true ? gRed : gGreen),
                child: Text(mem['isActive'] == true ? 'Disable' : 'Enable'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editMember(Json? m) async {
    final name = TextEditingController(text: m?['name']);
    final email = TextEditingController(text: m?['email']);
    final role = TextEditingController(text: m?['role'] ?? 'Member');
    final avatar = TextEditingController(text: m?['avatarUrl']);
    final reg = TextEditingController();
    var isAdmin = m?['isAdmin'] == true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(m == null ? 'Add member' : 'Edit ${m['dexId']}'),
          content: SizedBox(
            width: 400,
            child: ListView(
              shrinkWrap: true,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reg,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Registration number (login)',
                    helperText: m == null ? null : 'Leave blank to keep current',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: role,
                  decoration: const InputDecoration(labelText: 'GDG role'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: avatar,
                  decoration: const InputDecoration(labelText: 'Avatar URL (optional)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Organizer (admin)'),
                  value: isAdmin,
                  onChanged: (v) => setLocal(() => isAdmin = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SAVE')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final body = {
      'name': name.text,
      'email': email.text,
      'role': role.text,
      'avatarUrl': avatar.text.trim(),
      'isAdmin': isAdmin,
      if (reg.text.trim().isNotEmpty) 'regNo': reg.text,
    };
    await _run(
      () => m == null ? Api.post('admin/members', body) : Api.patch('admin/members/${m['dexId']}', body),
      m == null ? 'Member added' : 'Saved',
    );
  }
}

String _fmt(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
