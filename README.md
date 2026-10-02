# GDGdex — *Gotta GDG 'em all.*

Meet people → scan their GDGdex QR (or type their passkey) → collect them. Most unique entries when the event ends wins.

- `app/`: Flutter web client (mobile-first, dark/light).
- `server/`: Dart `shelf` API + SQLite. It also serves the built web app from the same origin, so login is a plain HttpOnly cookie.

## Run locally

```bash
cd app && flutter build web            # build the client once (rebuild after UI changes)
cd ../server
dart run bin/import.dart ~/Downloads/gdgdex_participants.csv   # preload roster into gdgdex.db
dart run bin/server.dart               # http://localhost:8080
```

For hot reload, keep the server running and use `cd app && flutter run -d chrome`. `web_dev_config.yaml` proxies `/api/` to :8080.

Tests: `cd server && dart test`. They cover duplicates, self-collection, invalid passkeys, concurrency, event state, admin authz and the leaderboard.

## Roster CSV

Header: `name,email,reg_no,role[,is_admin,is_active,gdgdex_id,passkey,avatar_url]`. Extra columns are ignored.
`gdgdex_id`/`passkey` are kept if present, otherwise generated. Re-running the import skips emails that already exist.
Registration numbers are stored only as salted HMAC hashes. **Never commit the roster CSV.**

## Event day

1. Deploy over **HTTPS**, because phones block the camera on plain http. Set `SECURE_COOKIES=1`.
2. An organizer (`is_admin`) opens **⋯ → Admin dashboard** and presses **START EVENT**, then **END EVENT** when done. Ending freezes the leaderboard, keeps all data and shows the winner.
3. Projector: open `/#/board`. It shows the big leaderboard, a live feed of new discoveries and a join QR, refreshing every 4s.
4. Printed badges: the admin print icon opens every member's QR + passkey as A4 lanyard cards, for anyone without a working phone.
5. Exports: the admin download icon gives the members+counts CSV, the full collections CSV and a SQLite backup.
6. Backups: the server also snapshots the DB every 5 minutes into `BACKUP_DIR` (default `<db dir>/backups`) and keeps the newest 24.

## Deploy (Docker)

```bash
docker build -t gdgdex .
docker run -p 8080:8080 -v gdgdex-data:/data -e SECURE_COOKIES=1 gdgdex
docker run --rm -v gdgdex-data:/data -v $PWD/roster.csv:/roster.csv gdgdex /opt/gdgdex/import/bundle/bin/import /roster.csv
```

SQLite needs a **persistent disk** (a VM, or Fly/Railway with a volume). Stateless hosts like Cloud Run would lose data. Run a single instance.

## Rules enforced server-side

- `UNIQUE(collector_id, collected_id)` and `CHECK(collector_id <> collected_id)` in the DB, plus `INSERT … ON CONFLICT DO NOTHING` inside a transaction that also checks the event is `ACTIVE`.
- The QR encodes `GDGDEX:<passkey>`. Collection accepts only the passkey and never the public `GDG-###` number, so nobody can enumerate entries.
- Rate limits: login (10 per email / 5 min) and lookup/collect (30 per user / min).
- Disabled members can't log in, can't be collected, and are hidden from rankings.
- Leaderboard: unique count desc. Ties go to whoever reached that count first.
