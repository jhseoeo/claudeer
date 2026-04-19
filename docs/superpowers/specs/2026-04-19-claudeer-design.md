# Claudeer - Desktop Mascot App Design Spec

## Overview

macOS 데스크톱 마스코트 앱. 사용자가 지정한 스프라이트 캐릭터가 화면 위를 돌아다니다가, Claude Code 세션 이벤트가 발생하면 소리와 말풍선으로 알려준다.

대상: 개발자. UI는 최소한으로, 리소스 커스터마이징은 파일 기반 + README 가이드.

## Tech Stack

- **SwiftUI + AppKit 하이브리드**
  - AppKit: 투명 오버레이 NSWindow (캐릭터 렌더링, 클릭 통과)
  - SwiftUI: 메뉴바 드롭다운 설정 UI
  - Foundation: Unix 소켓 서버
  - AVFoundation: 사운드 재생

## Architecture

앱 자체가 데몬 역할을 겸한다. 별도 데몬 프로세스 없음.

```
Claude Code Hook Scripts (Python) ──(Unix Socket)──> macOS App
                                                       |
                                                  EventServer (소켓 리스닝)
                                                       |
                                                 NotificationManager
                                                  |           |
                                            SpriteEngine   SoundPlayer
                                                  |
                                             OverlayWindow (transparent NSWindow)
                                                  |
                                             MenuBarController (settings)
```

앱 실행 → 소켓 열림 + 캐릭터 등장. 앱 종료 → 소켓 없음 → 훅은 조용히 실패 (fire-and-forget).

## Project Structure (Claude Code Plugin)

```
claudeer/
  .claude-plugin/plugin.json    # 플러그인 매니페스트
  hooks/                        # SessionStart, Stop, Notification 훅 (Python)
  skills/                       # 설정 가이드 등
  app/                          # Swift 소스코드 (Xcode project)
    Sources/
    Resources/                  # 사용자 커스텀 리소스 (sprites, sounds, config)
    Package.swift
```

설치: `claude plugin add` → 훅 등록. `swift build` → 앱 빌드. 앱 실행 → 동작 시작.

## Events

| Event | Hook Trigger | Character Reaction |
|-------|-------------|-------------------|
| `session_start` | SessionStart | 등장 애니메이션 + 대사 |
| `need_input` | Notification / Stop | alert 애니메이션 + 소리 + 말풍선 |
| `session_end` | Stop (종료 시) | 퇴장 애니메이션 + 대사 |

비정상 종료 감지: 앱이 알고 있는 세션 PID를 주기적으로 체크 (약 10초 간격).

## Resource Structure

사용자가 빌드 시점에 지정된 위치에 리소스 파일을 배치한다.

```
Resources/
  sprites/
    idle.gif          # 기본 대기 상태 (필수)
    walk.gif          # 이동 중
    alert.gif         # 알림 반응
  sounds/
    session_start.wav
    need_input.wav
    session_end.wav
  config.json
```

- GIF/APNG: 애니메이션으로 재생
- PNG: 정적 이미지로 표시
- 파일이 없으면 무시 (소리 없음, idle 스프라이트로 대체 등)

## config.json

```json
{
  "default_area": "bottom",
  "speeches": {
    "session_start": "일하러 왔다!",
    "need_input": "주인님~ 확인해주세요!",
    "session_end": "수고했어요~"
  }
}
```

## Area Presets

메뉴바 드롭다운에서 선택 가능한 캐릭터 활동 영역:

- `full_screen`: 전체 화면
- `bottom`: 하단 바닥
- `top`: 상단
- `menubar`: 메뉴바 근처
- `right_quarter`: 오른쪽 1/4
- `left_quarter`: 왼쪽 1/4

각 프리셋은 화면 기준 `CGRect` 영역으로 정의. 캐릭터는 해당 영역 내에서만 이동.

## Menu Bar UI

메뉴바 아이콘 클릭 시 드롭다운:

- 영역 프리셋 선택 (라디오 버튼)
- 볼륨 슬라이더
- 일시정지 / 종료

## Components

| Component | Role |
|-----------|------|
| `EventServer` | Unix 소켓 서버. 훅 스크립트에서 오는 JSON 이벤트 수신 |
| `SpriteEngine` | 스프라이트 로드, 애니메이션 상태 관리, 이동 로직 |
| `OverlayWindow` | 투명 최상위 NSWindow, 마우스 클릭 통과 |
| `SoundPlayer` | 이벤트별 사운드 파일 재생 |
| `MenuBarController` | 메뉴바 아이콘 + SwiftUI 설정 드롭다운 |
| `SpeechBubble` | 말풍선 뷰. 캐릭터 위에 표시, 일정 시간 후 자동 소멸 |
| `NotificationManager` | 이벤트 수신 -> 적절한 캐릭터 반응 트리거 |

## Hook Script (Claude Code side)

Claude Code 훅에서 앱으로 이벤트를 보내는 경량 스크립트:

```python
import socket, json
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect("/tmp/claudeer.sock")
sock.send(json.dumps({"event": "need_input", "session_id": "abc123"}).encode() + b"\n")
sock.close()
```

이 스크립트는 Claude Code 플러그인의 훅으로 등록된다.

## Socket Protocol

소켓 경로: `/tmp/claudeer.sock`

요청 (hook -> app):
```json
{"event": "session_start|need_input|session_end", "session_id": "...", "pid": 12345}
```

응답 (app -> hook):
```json
{"ok": true}
```

## Out of Scope

- 캐릭터 디자인 도구 / 에디터
- 크로스 플랫폼 지원
- 네트워크 원격 알림
- 별도 데몬 프로세스 (앱이 데몬 역할 겸임)
