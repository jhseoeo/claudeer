# Claudeer

Desktop mascot app for macOS that reacts to Claude Code session events.

A sprite character roams your screen and alerts you with animations,
speech bubbles, and sounds when Claude Code needs your attention.

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode 15+
- Claude Code with plugin support

## Setup

### 1. Build

```bash
swift build -c release
```

### 2. Install as Claude Code plugin

```bash
claude plugin add /path/to/claudeer
```

### 3. Run the app

```bash
.build/release/Claudeer
```

메뉴바에 🐾 아이콘이 나타나면 정상 실행. 캐릭터는 스프라이트를 등록하기 전까지 화면에 안 보입니다.

### 4. Customize via Preferences

🐾 → "Preferences..." 클릭하면 설정 윈도우가 열립니다. 등록한 파일은 `~/Library/Application Support/Claudeer/`에 복사되며, 변경 즉시 반영됩니다 (재시작 불필요).

**Sprites** — Idle / Walk / Alert. 형식: PNG, JPG, GIF.

| Slot | 용도 |
|------|------|
| `idle` | 기본 정지 상태 (없으면 캐릭터 안 보임) |
| `walk` | 이동 중 애니메이션 |
| `alert` | 이벤트 발생 시 반응 |

`idle`만 필수, 나머지는 없으면 `idle`로 대체.

> **GIF vs APNG**: GIF는 1비트 알파만 지원해서 외곽선이 들쑥날쑥할 수 있어요. 부드러운 외곽선이 필요하면 **APNG**를 쓰세요. 변환은 `ezgif.com` 또는 `ffmpeg -i frame_%03d.png -plays 0 out.apng`.
>
> **APNG 등록 팁**: macOS에 APNG 시스템 UTType이 없어서 파일 피커에서 `.apng` 확장자가 안 보일 수 있어요. APNG는 PNG와 호환되니까 `mv myanim.apng myanim.png` 으로 이름만 바꿔서 등록하면 애니메이션이 정상 재생됩니다.

**Sounds** — Session Start / Need Input / Session End. 형식: WAV, MP3, AIFF, M4A. 전부 선택사항.

**Speeches** — 각 이벤트의 말풍선 텍스트. 텍스트 필드 편집 후 포커스 해제하면 자동 저장.

### Area Presets

Choose where the mascot roams via the menu bar icon (🐾):

- **Full Screen** — entire screen
- **Bottom** — bottom edge (default)
- **Top** — top edge
- **Menu Bar** — near the menu bar
- **Right 1/4** — right quarter
- **Left 1/4** — left quarter

## How It Works

1. The app opens a Unix socket at `/tmp/claudeer.sock`
2. Claude Code hooks (installed via plugin) send JSON events to this socket
3. The app reacts with character animations, speech bubbles, and sounds
4. If the app isn't running, hooks silently fail (no impact on Claude Code)
