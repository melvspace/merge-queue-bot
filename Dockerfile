FROM dart:3.13.5-sdk AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get --enforce-lockfile
COPY . .
RUN dart build cli --target bin/merge_queue_bot.dart --output build

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 10001 bot \
    && mkdir /data && chown bot:bot /data
COPY --from=build /app/build/bundle/ /app/
USER bot
WORKDIR /data
ENTRYPOINT ["/app/bin/merge_queue_bot"]
CMD ["--config", "/config/config.yaml"]
