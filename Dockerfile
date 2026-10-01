# --- web app ---
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /src/app
COPY app/pubspec.* ./
RUN flutter pub get
COPY app/ ./
RUN flutter build web --release

# --- server ---
FROM dart:stable AS server
WORKDIR /src/server
COPY server/pubspec.* ./
RUN dart pub get
COPY server/ ./
RUN dart build cli -t bin/server.dart -o /out/server && dart build cli -t bin/import.dart -o /out/import

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=server /out /opt/gdgdex
COPY --from=web /src/app/build/web /opt/gdgdex/web
ENV PORT=8080 WEB_DIR=/opt/gdgdex/web DB_PATH=/data/gdgdex.db
VOLUME /data
EXPOSE 8080
CMD ["/opt/gdgdex/server/bundle/bin/server"]
