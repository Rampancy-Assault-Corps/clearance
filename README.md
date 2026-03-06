# RACBot_NYXX

Dart/Nyxx migration of RACBot with TOML hot-reload and command/event parity.

## Requirements

- Dart SDK 3.10+

## Quick Start

1. Copy `config/bot.toml.example` to `config/bot.toml`.
2. Set `runtime.discord_token` in `config/bot.toml` or set `DISCORD_TOKEN`.
3. Run:

```bash
dart pub get
dart run bin/racbot_nyxx.dart --config=config/bot.toml
```

## CLI Overrides

- `--config=<path>`
- `--discord-token=<token>`
- `--owner-ids=<id1,id2,...>`
- `--data-dir=<path>`

## Source Run Script

```bash
./tool/run.sh
```

## Compiled Build

```bash
./tool/compile.sh
./tool/run_compiled.sh
```

Targets:

- `./tool/compile.sh --target exe`
- `./tool/compile.sh --target exe --target-os linux --target-arch x64`
- `./tool/compile.sh --target jit-snapshot`
- `./tool/compile.sh --target aot-snapshot`
- `./tool/compile.sh --target kernel`

## Docker

```bash
docker compose up --build -d
```

Volumes:

- `./data` -> `/app/data`
- `./config` -> `/app/config`
