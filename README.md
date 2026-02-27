# ses

Speech Event Stream CLI for macOS. It captures audio from a selected input device and emits **JSONL** events for UI, automation, and downstream processing.

This project is designed as an **event bus**: you can consume low-level events (`level`, `speech_start`, `delta`, `commit`, etc.) and build your own pipeline on top.

---

## Supported macOS

- macOS 26+

---

## Install (Homebrew)

`ses` is distributed via Homebrew tap:

```/dev/null/command.sh#L1-2
brew tap rioriost/homebrew-ses
brew install ses
```

---

## Quick Start

List input devices:

```/dev/null/command.sh#L1-1
ses --list-devices
```

Start streaming with a specific device:

```/dev/null/command.sh#L1-1
ses --device-id 2
```

Pretty-printed output:

```/dev/null/command.sh#L1-1
ses --device-id 2 --pretty
```

---

## Output Format (JSONL)

Each line is a JSON object. All events include:

- `type` (string): event type
- `ts_ms` (number): timestamp in milliseconds
- `session` (string): session ID (omitted if `--no-session`)
- `schema_version` (number): schema version (present on `status` events)

### Event Types

| type | description |
|---|---|
| `status` | lifecycle/metadata |
| `level` | audio level snapshot |
| `speech_start` | VAD start |
| `speech_end` | VAD end |
| `silence` | silence threshold reached |
| `partial` | incremental transcript (full text) |
| `delta` | incremental transcript (diff only) |
| `final` | final transcript (full text) |
| `commit` | finalized chunk for LLM/processing |
| `error` | machine-readable errors |

---

## Event Schema (current)

### `status`
Emitted at startup, when listing devices, and when the stream enters `listening`.

Startup includes the resolved configuration and output flags so you can confirm runtime settings early.

Example (startup):

```/dev/null/example.json#L1-23
{
  "type": "status",
  "state": "starting",
  "schema_version": 1,
  "locale": "ja_JP",
  "device_id": 2,
  "recommended": false,
  "pretty": false,
  "no_session": false,
  "debug": false,
  "mcp": false,
  "level_interval_ms": 200,
  "vad_threshold_db": -30,
  "vad_hang_ms": 250,
  "vad_ema_alpha": 0.2,
  "commit_silence_ms": 700,
  "warmup_ms": 1200,
  "commit_on_speech_end": true,
  "ts_ms": 123,
  "session": "..."
}
```

Example (stream start):

```/dev/null/example.json#L1-16
{
  "type": "status",
  "state": "listening",
  "schema_version": 1,
  "device": "Your Microphone",
  "device_uid": "device-uid",
  "locale": "ja_JP",
  "recommended": false,
  "level_interval_ms": 200,
  "vad_threshold_db": -30,
  "vad_hang_ms": 250,
  "vad_ema_alpha": 0.2,
  "commit_silence_ms": 700,
  "warmup_ms": 1200,
  "commit_on_speech_end": true,
  "ts_ms": 123,
  "session": "..."
}
```

Example (`--list-devices`):

```/dev/null/example.json#L1-10
{
  "type": "status",
  "state": "devices",
  "schema_version": 1,
  "inputs": [
    { "id": 0, "name": "Mic A", "uid": "..." },
    { "id": 1, "name": "Mic B", "uid": "..." }
  ],
  "ts_ms": 123,
  "session": "..."
}
```

### `level`
Snapshot of the audio level.

```/dev/null/example.json#L1-7
{
  "type": "level",
  "audio_level_db": -62.1,
  "vad_db": -60.9,
  "speaking": false,
  "sample_rate": 48000,
  "ts_ms": 123,
  "session": "..."
}
```

### `speech_start` / `speech_end`
VAD start/end markers. Required fields: `audio_level_db`, `vad_db`, `utterance_id`.

```/dev/null/example.json#L1-6
{
  "type": "speech_start",
  "audio_level_db": -24.1,
  "vad_db": -29.1,
  "utterance_id": 3,
  "ts_ms": 123,
  "session": "..."
}
```

### `silence`
Emitted when silence threshold is reached (used to trigger commit). Required fields: `audio_level_db`, `vad_db`, `utterance_id`, `silence_ms`.

```/dev/null/example.json#L1-8
{
  "type": "silence",
  "audio_level_db": -45.0,
  "vad_db": -40.0,
  "utterance_id": 3,
  "silence_ms": 700,
  "ts_ms": 123,
  "session": "..."
}
```

### `partial` / `delta` / `final`
Transcript events.

- `partial`/`final` include the **full text**
- `delta` includes **only the incremental diff**
- Required fields: `partial`/`final` -> `seq`, `text`; `delta` -> `seq`, `delta`

```/dev/null/example.json#L1-6
{
  "type": "delta",
  "seq": 12,
  "delta": "hello",
  "ts_ms": 123,
  "session": "..."
}
```

```/dev/null/example.json#L1-6
{
  "type": "partial",
  "seq": 12,
  "text": "hello world",
  "ts_ms": 123,
  "session": "..."
}
```

### `commit`
Finalized text chunk (recommended input for LLMs). Required fields: `commit_reason`, `commit_from_seq`, `commit_to_seq`, `commit_span_ms`.

```/dev/null/example.json#L1-12
{
  "type": "commit",
  "commit_id": 4,
  "commit_reason": "speech_end",
  "text": "hello world",
  "commit_from_seq": 10,
  "commit_to_seq": 12,
  "commit_span_ms": 820,
  "audio_level_db": -41.2,
  "vad_db": -38.7,
  "utterance_id": 3,
  "ts_ms": 123,
  "session": "..."
}
```

### `error`
Machine-readable error. Required fields: `code`, `message`, `recoverable` (always present). Optional: `hint`, `underlying`.

```/dev/null/example.json#L1-7
{
  "type": "error",
  "code": "device_disconnected",
  "message": "Device was disconnected.",
  "recoverable": false,
  "ts_ms": 123,
  "session": "..."
}
```

Error codes (fixed list):

- `mic_permission_denied`
- `speech_permission_denied`
- `device_not_found`
- `device_input_failed`
- `device_disconnected`
- `recognizer_init_failed`
- `recognizer_unavailable`
- `recognition_task_error`

---

## CLI Options (current)

- `--list-devices`
- `--device-id <int>`
- `--locale <locale_id>`
- `--pretty`
- `--no-session`
- `--debug`
- `--mcp`
- `--recommended`
- `--vad-threshold-db <double>`
- `--vad-hang-ms <int>`
- `--vad-ema-alpha <double>`
- `--level-interval-ms <int>`
- `--commit-silence-ms <int>`
- `--warmup-ms <int>`
- `--commit-on-speech-end` / `--no-commit-on-speech-end`
- `--watchdog-timeout-ms <int>`
- `--watchdog-interval-ms <int>`

---

## Architecture (high-level)

- `Sources/cli`: CLI entrypoint (`ses`) and argument parsing
- `Sources/ses`: Core pipeline (Audio → VAD → Speech → Events)
- `Sources/ses/MCP`: MCP server adapter and event buffer
- `Sources/sesTestRunner`: Internal test runner and utilities

## Output/Events (notes)

- Events are emitted as JSONL to stdout (one JSON object per line).
- `--no-session` omits the `session` field from all events.
- `--mcp` runs the MCP JSON-RPC server instead of direct JSONL output.

---

## Implementation Status (current)

The current implementation provides:

- JSONL event stream for audio level, VAD, transcripts, commits, and errors
- Device discovery (`--list-devices`) and explicit device selection
- VAD configuration and commit policy controls
- Speech recognition via Apple’s Speech framework (`SFSpeechRecognizer`)
- Localized output messages (English/Japanese)

---

## Developer Testing

Build the debug binary:

```/dev/null/command.sh#L1-1
make build
```

Run the test runner:

```/dev/null/command.sh#L1-1
make test
```

Run coverage report:

```/dev/null/command.sh#L1-1
make coverage
```

Run CI (build + tests + coverage):

```/dev/null/command.sh#L1-1
make ci
```

Notes:

- Some CLI tests may skip when microphone/speech permissions are not granted.
- Coverage uses `llvm-profdata` and `llvm-cov` via Xcode toolchain.

---

## Localization

Messages are localized via `Localizable.strings` (English/Japanese).

---

## License

MIT