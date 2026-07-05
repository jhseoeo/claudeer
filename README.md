# Claudeer

Desktop mascot app for macOS that reacts to Claude Code session events.

A sprite character roams your screen and changes state — `idle` while Claude is
waiting for your input, `working` while Claude is processing — with animations,
speech bubbles, and sounds at each transition.

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode 15+
- Claude Code with plugin support

## Setup

### 1. Build the app bundle

```bash
./scripts/build-app.sh
```

`dist/Claudeer.app` 가 만들어집니다 (메뉴바 앱, dock 아이콘 없음). `swift build -c release` 단독으로는 CLI 바이너리만 나오니 이 스크립트를 쓰는 걸 권장합니다.

### 2. Install as Claude Code plugin

이 저장소가 자체 marketplace를 갖고 있어요. 한 번만 등록하면 됩니다.

```bash
# 마켓플레이스 등록 (저장소 경로)
claude plugin marketplace add /path/to/claudeer

# 플러그인 설치
claude plugin install claudeer@claudeer-marketplace
```

> Hook은 Claude Code 세션 시작 시점에 로드되므로, 설치 후엔 **현재 열려있는 Claude 세션을 끝내고 새로 시작해야** hook이 mascot에 이벤트를 보냅니다. 이미 켜져 있던 세션에서는 동작 안 함.

### 3. Run the app

```bash
open dist/Claudeer.app
```

또는 `cp -R dist/Claudeer.app /Applications/` 로 설치 후 Launchpad/Spotlight에서 실행.

메뉴바에 🐾 아이콘이 나타나면 정상 실행. 캐릭터는 스프라이트를 등록하기 전까지 화면에 안 보입니다.

### 4. Customize via Preferences

🐾 → "Preferences..." 클릭하면 설정 윈도우가 열립니다. 등록한 파일은 `~/Library/Application Support/Claudeer/`에 복사되며, 변경 즉시 반영됩니다 (재시작 불필요).

**Sprites** — 두 가지 상태. 형식: PNG, JPG, GIF.

| Slot | 의미 |
|------|------|
| `idle` | Claude가 유저 입력을 기다리는 상태 (필수, 없으면 캐릭터 안 보임) |
| `working` | 프롬프트를 받아 처리 중인 상태 (없으면 `idle`로 대체) |

> **GIF vs APNG**: GIF는 1비트 알파만 지원해서 외곽선이 들쑥날쑥할 수 있어요. 부드러운 외곽선이 필요하면 **APNG**를 쓰세요. 변환은 `ezgif.com` 또는 `ffmpeg -i frame_%03d.png -plays 0 out.apng`.
>
> **APNG 등록 팁**: macOS에 APNG 시스템 UTType이 없어서 파일 피커에서 `.apng` 확장자가 안 보일 수 있어요. APNG는 PNG와 호환되니까 `mv myanim.apng myanim.png` 으로 이름만 바꿔서 등록하면 애니메이션이 정상 재생됩니다.

**Sounds** — `idle` / `working` 슬롯. 형식: WAV, MP3, AIFF, M4A. 전부 선택사항.

각 슬롯에 **Loop** 체크박스가 있어요:
- **Off (기본)**: 그 상태로 전이하는 순간 1회만 재생 (알림용 효과음에 적합)
- **On**: 그 상태에 있는 동안 무한 반복 재생 (working 동안 BGM 깔고 싶을 때 등). 다른 상태로 전이하면 즉시 멈춤.

**Speeches** — 각 상태로 전이할 때 표시될 말풍선 텍스트. 텍스트 필드 편집 후 포커스 해제하면 자동 저장.

**Movement** — 캐릭터의 화면 내 이동을 제어.

| 항목 | 의미 |
|------|------|
| `Move while idle` | idle 상태일 때 어슬렁거릴지 (체크 해제 시 그 상태에선 정지) |
| `Move while working` | working 상태일 때 어슬렁거릴지 |
| `Speed` | 글로벌 이동 속도 슬라이더 (Slow ↔ Fast). 슬라이더 움직이면 즉시 반영 |
| `Social encounters` | 여러 세션일 때 평소엔 각자 배회하다가, 가까워진 애들끼리 잠깐(≈3초) 모여 폴짝폴짝 뛰며 ❤️ 하고 다시 흩어짐. 근처를 지나가는 애들이 합류해 여러 마리가 우르르 모임. 한 번 모인 캐릭터는 60초간 아무와도 안 모이고 배회만 하다 다시 참여. 기본 켜짐 |
| `Gather to the mouse cursor` | 커서 일정 반경 안의 캐릭터가 마우스로 모임 (필요하면 로밍 영역을 벗어나서라도). 기본 꺼짐 |
| `Cursor range` | 위 옵션의 반경 슬라이더 (Near ↔ Far) |

**Interactions** — 캐릭터 클릭/드래그 시 추가 효과. 전부 옵셔널.

| Slot | 의미 |
|------|------|
| `Drag` 스프라이트 | 드래그 중 표시할 이미지 |
| `Click` 스프라이트 | 클릭 시 1초 동안 표시될 이미지 |
| `Drag press` 사운드 | 드래그 시작 시 1회 재생 |
| `Drag release` 사운드 | 드래그 종료 (마우스 release) 시 1회 재생 |
| `Click` 사운드 | 클릭 시 1회 재생 |

> 캐릭터 위에 마우스를 올리면 클릭 가능. mouseDown 후 4px 이상 움직이면 드래그로 인식. 드래그 중에는 캐릭터의 자체 이동이 멈춥니다.

**Notifications (ntfy.sh)** — Claude가 작업을 끝내고 입력을 기다리는 순간을 [ntfy.sh](https://ntfy.sh) 푸시로 폰·데스크톱에 받기. 자리를 비웠을 때 유용해요. 전부 옵셔널.

| 항목 | 의미 |
|------|------|
| `Push to ntfy.sh when a session goes idle` | 켜면 세션이 idle로 전환될 때마다 푸시 발송 |
| `Server` | ntfy 서버 주소 (기본 `https://ntfy.sh`, 셀프호스팅 가능) |
| `Topic` | 구독할 토픽 이름. 추측 어려운 고유 문자열 권장 (공개 토픽은 누구나 구독 가능) |
| `Token` | 보호된/예약된 토픽용 액세스 토큰 (선택) |
| `Send test` | 현재 설정으로 테스트 푸시 1회 발송 |

푸시 **제목**은 세션 이름, **본문**은 위 `idle` 말풍선 텍스트예요. ntfy 앱이나 `https://<server>/<topic>` 에서 같은 토픽을 구독하면 받을 수 있어요. 앱(메뉴바 데몬)이 떠 있어야 발송됩니다.

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
2. Claude Code hooks (installed via plugin) send state transitions to this socket:
   - `SessionStart` → `idle` (등록만, 첫 진입은 무음)
   - `UserPromptSubmit` → `working`
   - `Stop` → `idle`
   - `Notification` → `idle`
3. 상태가 실제로 바뀌는 순간에만 스프라이트 교체 + 사운드 + 말풍선 (+ 설정 시 `idle` 전환마다 ntfy.sh 푸시)
4. If the app isn't running, hooks silently fail (no impact on Claude Code)
