---
trigger: model_decision
description: Apply ONLY when writing, modifying, or reviewing CC:Tweaked Lua (.lua) files or CraftOS-PC emulator runners. Do NOT apply to general chat, markdown docs, or non-Lua tasks.
---

# CC:Tweaked Lua Runtime Constraints

1. **타깃 런타임**:
   - CC:Tweaked 1.109+ / 1.112+ (ComputerCraft / Cobalt Lua 5.2 런타임 호환).
   - 가변 인자는 `...`(구형 `arg` 테이블 금지), 환경 제어는 `_ENV`(`getfenv`/`setfenv` 금지) 사용, 바이너리 청크 미지원.

2. **문법 및 연산자 제약 (Lua 5.2)**:
   - Lua 5.3+ 연산자 사용 금지: 정수 나눗셈(`//`), 비트 연산자(`&`, `|`, `~`, `<<`, `>>`).
   - 비트 연산은 `bit32` 전역 라이브러리(`bit32.band`, `bit32.bor`, `bit32.rshift` 등), 정수 나눗셈은 `math.floor(a / b)` 사용.

3. **호스트 OS API 사용 금지**:
   - 표준 Lua 호스트 API(`os.execute`, `io.popen`, `os.exit`, `os.remove`, `os.rename`)는 CraftOS에서 비활성화되어 있으므로 사용 금지.
   - CraftOS 네이티브 API 사용: 파일 시스템 `fs.*`(`fs.delete`, `fs.move`, `fs.open`), 쉘 실행 `shell.run`, 종료 `os.shutdown` 또는 `error()`.

4. **이벤트 루프 및 양보 (Yield) 필수**:
   - 무한 루프(`while true do`, `repeat ... until false`) 및 장시간 반복 루프 내부에는 반드시 이벤트 대기나 슬립(`os.pullEvent()`, `sleep()`, `rednet.receive()`)을 포함해 `Too long without yielding` 크래시를 방지한다.

5. **변수 및 스택 한계**:
   - 단일 함수/청크 스코프 내 지역 변수(local variables) 200개 미만, 클로저 업밸류(upvalues) 60개 미만 유지.
