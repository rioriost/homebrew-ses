# ses — Speech Event Stream CLI

`ses` は macOS 向けの **Speech Event Stream** CLI です。  
音声入力をストリーミング処理し、**JSONL（1行1JSON）** でイベントを出力します。

- VAD（発話開始/終了）
- 音量レベル
- 音声認識結果（partial / delta / final）
- commit（無音などの条件で確定したテキスト）

---

## 対応 macOS

- macOS 26 以上

---

## インストール（Homebrew）

Homebrew の tap `rioriost/homebrew-ses` からインストールできます。

```/dev/null/command.sh#L1-2
brew tap rioriost/homebrew-ses
brew install ses
```

---

## 使い方（基本）

### デバイス一覧

```/dev/null/command.sh#L1-1
ses --list-devices
```

読みやすいJSONで出力：

```/dev/null/command.sh#L1-1
ses --list-devices --pretty
```

### 録音開始（デバイス指定）

```/dev/null/command.sh#L1-1
ses --device-id 2
```

---

## イベントスキーマ（JSONL）

各行が1つのイベントです。

共通フィールド：

- `type` (string): イベント種別
- `ts_ms` (number): ミリ秒タイムスタンプ
- `session` (string): セッションID（`--no-session` で省略可能）
- `schema_version` (number): スキーマバージョン（status系イベントに含まれる）

---

### 1) status

```/dev/null/event.json#L1-10
{
  "type": "status",
  "ts_ms": 123,
  "session": "...",
  "state": "listening",
  "schema_version": 1,
  "device": "Mic Name",
  "device_uid": "UID",
  "locale": "ja_JP"
}
```

主な `state` 値：

- `devices`（`--list-devices`）
- `listening`
- `audio_started`
- `debug`（`--debug` 時）

---

### 2) level（音量レベル）

```/dev/null/event.json#L1-8
{
  "type": "level",
  "ts_ms": 1234,
  "session": "...",
  "audio_level_db": -42.1,
  "vad_db": -38.5,
  "speaking": false,
  "sample_rate": 48000
}
```

---

### 3) speech_start / speech_end（VADイベント）
必須フィールド: `audio_level_db`, `vad_db`, `utterance_id`。

```/dev/null/event.json#L1-7
{
  "type": "speech_start",
  "ts_ms": 2000,
  "session": "...",
  "audio_level_db": -30.5,
  "vad_db": -28.0,
  "utterance_id": 1
}
```

`speech_end` も同じフィールド構成です。

---

### 4) silence（静寂）
必須フィールド: `audio_level_db`, `vad_db`, `utterance_id`, `silence_ms`。

```/dev/null/event.json#L1-8
{
  "type": "silence",
  "ts_ms": 3500,
  "session": "...",
  "audio_level_db": -50.0,
  "vad_db": -45.0,
  "utterance_id": 1,
  "silence_ms": 700
}
```

---

### 5) partial / final（全文）
必須フィールド: `seq`, `text`。

```/dev/null/event.json#L1-6
{
  "type": "partial",
  "ts_ms": 3000,
  "session": "...",
  "seq": 12,
  "text": "こんにちは"
}
```

`final` も同様です。

---

### 6) delta（差分）
必須フィールド: `seq`, `delta`。

```/dev/null/event.json#L1-6
{
  "type": "delta",
  "ts_ms": 3100,
  "session": "...",
  "seq": 12,
  "delta": "にちは"
}
```

---

### 7) commit（確定テキスト）
必須フィールド: `commit_reason`, `commit_from_seq`, `commit_to_seq`, `commit_span_ms`。

```/dev/null/event.json#L1-11
{
  "type": "commit",
  "ts_ms": 4000,
  "session": "...",
  "commit_id": 3,
  "commit_reason": "silence",
  "text": "こんにちは",
  "commit_from_seq": 10,
  "commit_to_seq": 12,
  "commit_span_ms": 820,
  "audio_level_db": -45.0,
  "vad_db": -40.0,
  "utterance_id": 1
}
```

`commit_reason` は `speech_end` / `silence` など。

---

### 8) error（機械可読）
必須フィールド: `code`, `message`, `recoverable`（常に含まれる）。任意: `hint`, `underlying`。

```/dev/null/event.json#L1-7
{
  "type": "error",
  "ts_ms": 5000,
  "session": "...",
  "code": "device_disconnected",
  "message": "デバイスが切断されました。",
  "recoverable": false
}
```

エラーコード（固定リスト）:

- `mic_permission_denied`
- `speech_permission_denied`
- `device_not_found`
- `device_input_failed`
- `device_disconnected`
- `recognizer_init_failed`
- `recognizer_unavailable`
- `recognition_task_error`

---

## 主要オプション

- `--list-devices`
- `--device-id <id>`
- `--locale <identifier>`
- `--pretty`
- `--no-session`
- `--debug`
- `--mcp`
- `--version`
- `--recommended`

VAD/commit/監視系：

- `--vad-threshold-db <dB>`
- `--vad-hang-ms <ms>`
- `--vad-ema-alpha <alpha>`
- `--commit-silence-ms <ms>`
- `--warmup-ms <ms>`
- `--commit-on-speech-end` / `--no-commit-on-speech-end`
- `--watchdog-timeout-ms <ms>`
- `--watchdog-interval-ms <ms>`

---

## アーキテクチャ（概要）

- `Sources/cli`: CLI エントリポイント（`ses`）と引数解析
- `Sources/ses`: コアパイプライン（Audio → VAD → Speech → Events）
- `Sources/ses/MCP`: MCP サーバー連携とイベントバッファ
- `Sources/sesTestRunner`: 内部テストランナー/ユーティリティ

## 出力/イベント（メモ）

- イベントは JSONL（1行1JSON）で stdout に出力されます。
- `--no-session` で全イベントの `session` フィールドを省略します。
- `--mcp` は JSONL 出力ではなく MCP の JSON-RPC サーバーとして動作します。

---

## 実装状況（最新）

現時点で提供されている機能：

- 音量レベル / VAD / transcript / commit / error の JSONL イベント出力
- `--list-devices` によるデバイス列挙と明示的なデバイス指定
- VAD パラメータと commit ポリシーの設定
- Apple Speech フレームワーク（`SFSpeechRecognizer`）による音声認識
- 英語/日本語のローカライズ出力

---

## 開発者向け: テスト方法

ビルド（debug）:

```/dev/null/command.sh#L1-1
make build
```

テスト実行:

```/dev/null/command.sh#L1-1
make test
```

カバレッジ計測:

```/dev/null/command.sh#L1-1
make coverage
```

CI 相当（build + test + coverage）:

```/dev/null/command.sh#L1-1
make ci
```

補足:

- マイク/音声認識の権限がない場合、一部 CLI テストは SKIP されます。
- カバレッジは Xcode の `llvm-profdata` / `llvm-cov` を利用します。

---

## ローカライズ

出力メッセージは `Localizable.strings` によってローカライズされます。  
macOS の言語設定に応じて日本語/英語が自動で切り替わります。

---

## 目的

`ses` は **"イベントバス" としての音声ストリーム** を重視しています。  
GUI・録音制御・LLMパイプラインへの統合に向けて、  
`delta` と `commit` を明確に分離する設計です。
