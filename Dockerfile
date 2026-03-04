FROM dart:stable AS build

WORKDIR /app

COPY pubspec.yaml analysis_options.yaml ./
RUN dart pub get

COPY . .
RUN mkdir -p build \
    && dart run nyxx_commands:compile -o build/racbot_nyxx.g.dart bin/racbot_nyxx.dart \
    && mv build/racbot_nyxx.g.exe build/racbot_nyxx \
    && chmod +x build/racbot_nyxx

FROM debian:bookworm-slim

WORKDIR /app

RUN groupadd --system racbot && useradd --system --gid racbot racbot

COPY --from=build /app/build/racbot_nyxx /app/racbot_nyxx
COPY --from=build /app/config/bot.toml.example /app/config/bot.toml.example

RUN mkdir -p /app/data /app/config \
    && chown -R racbot:racbot /app \
    && chmod +x /app/racbot_nyxx

USER racbot

VOLUME ["/app/data", "/app/config"]

ENTRYPOINT ["/app/racbot_nyxx", "--config=/app/config/bot.toml"]
