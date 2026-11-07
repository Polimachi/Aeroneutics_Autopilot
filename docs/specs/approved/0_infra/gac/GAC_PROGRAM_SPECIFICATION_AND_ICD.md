# 지상 구역 및 에이프런 관제사(GAC) 시스템 및 통신 인터페이스 제어 규격서 (ICD)
> **Ground Apron Controller (GAC) System Specification & Interface Control Document (ICD)**  
> **프로젝트**: Universal Autonomous Flight Stack (SAS · VAS · Ground Infrastructure)  
> **문서 버전**: v1.1.4 (4대 비행 프로그램 최신 실측 구현 데이터 반영 양방향 동기화: Master ICD v1.20.0, SYSTEM v2.6.0, SAS v1.9.0, VAS v1.11.0, TCA v1.8.0, Alignment v2.4.0, LANDING_PAD v2.2.3, RUNWAY v1.10.3, DOCKING_ARM v1.10.3, GPS v2.0.3 전역 동기화)  
> **최종 수정일**: 2026-11-07  
> **대상 환경**: Minecraft CC:Tweaked (Ender Modem), Create: Aeronautics, Create: Avionics  
> **연관 규격서**: 
> - [AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md](../../../../system/AUTONOMOUS_FLIGHT_SYSTEM_ARCHITECTURE_AND_ICD.md) (마스터 ICD v1.20.0)
> - [SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md](../../../../system/SYSTEM_PROGRAM_RELATION_AND_PACKET_DIAGRAM.md) (전체 관계도 v2.6.0)
> - [SAS_PROGRAM_SPECIFICATION.md](../../../implemented/2_guidance/sas/SAS_PROGRAM_SPECIFICATION.md) (SAS 자율 항법 규격서 v1.9.0)
> - [VAS_PROGRAM_SPECIFICATION.md](../../../implemented/1_control/vas/VAS_PROGRAM_SPECIFICATION.md) (비행 제어 코어 v1.11.0)
> - [LANDING_PAD_SPECIFICATION_AND_ICD.md](../../0_ground/landing_pad/LANDING_PAD_SPECIFICATION_AND_ICD.md) (착륙패드 규격서 v2.2.3)
> - [RUNWAY_SPECIFICATION_AND_ICD.md](../../0_ground/runway/RUNWAY_SPECIFICATION_AND_ICD.md) (활주로 규격서 v1.10.3)
> - [DOCKING_ARM_SPECIFICATION_AND_ICD.md](../../0_ground/docking_arm/DOCKING_ARM_SPECIFICATION_AND_ICD.md) (도킹암 규격서 v1.10.3)
> - [GPS_PROGRAM_SPECIFICATION_AND_ICD.md](../../../implemented/0_infra/gps/GPS_PROGRAM_SPECIFICATION_AND_ICD.md) (GPS 규격서 v2.0.3)

---

## 1. 개요 및 계층형 시스템 범위 (Overview & Hierarchical Scope)

본 문서는 자율 비행체 시스템과 지상 시설물 간의 대규모 교통 체증을 해소하고, 특정 기지·버티포트·함선 섹터 내의 시설물 군(착륙패드, 활주로 유도로, 도킹 에이프런)을 총괄 관리·분배하는 **지상 구역 관제사(Ground Apron Controller, 이하 GAC) 노드**의 통신 프로토콜, 계층형 핸드오프 절차, 다속성 분배 알고리즘 및 상태 머신(FSM)을 정의한 세부 규격서입니다.

### 1.1 3대 관제 계층 (3-Tier Air Traffic & Ground Architecture)
본 규격 체계는 대공 공역 관리와 지상 국지 시설물 관리를 명확히 분리하는 3계층 아키텍처를 채택합니다:

1. **Tier 1: 통합 광역 관제탑 (Master / Tower ATC)**:
   - 기지/공항 공역을 총괄하며, 장거리 접근 기체의 진입 인가 및 적정 기지/섹터로의 관제 이양(Handoff)을 지휘합니다.
2. **Tier 2: 지상 구역 관제사 (Ground Apron Controller, GAC)**:
   - 특정 기지, 버티포트, 또는 함선 비행갑판의 지상 시설물 군을 총괄하는 중간 관리자 노드입니다.
   - 섹터 집약 비콘 송출, 다속성 최적 시설물 분배, 로컬 복행 중재, 지상 정박 및 이륙 상향 핸드오프를 전담합니다.
3. **Tier 3: 개별 시설물 노드 (Individual Facility Nodes)**:
   - 착륙패드(`PAD_xx`), 활주로(`RWY_xx`), 도킹암(`DOCK_xx`) 등 실제 물리 접지/결합을 담당하는 말단 노드입니다.
   - 직속 GAC와 로컬 백본망으로 연동되며, 기체와 1:1 전술 정밀 유도 스트리밍 및 물리 접지 감지에 집중합니다.

---

### 1.2 핵심 설계 원칙
1. **섹터 집약 비콘화 (Sector Aggregated Beacon, CH 50003 / Base_sec+2)**:
   - 개별 패드/시설물이 독립적으로 송출하던 1Hz 비콘을 상위 GAC 노드가 흡수·통합합니다.
   - GAC 노드가 관할 구역 내 시설물 전체의 가용 현황(`freePads`, `maxWeight`, `maxRadius`, 국지풍)을 집약한 단일 섹터 비콘(`MSG_FACILITY_BEACON`)을 CH 50003(Sector 0 대표) 또는 섹터 전용 비콘($Base_{\text{sec}}+2$)에 1Hz로 송출하여 CC:Tweaked 무선 모뎀의 패킷 트래픽을 극적으로 절감합니다.
2. **2단계 주파수 핸드오프 (Two-Stage Frequency Handoff)**:
   - 기체는 광역 접근 시 Tower ATC(`CH 50001`)와 교신하여 섹터 관제 채널($Base_{\text{sec}} + 0$)을 하달받고, GAC 주파수로 핸드오버하여 최종 착륙 시설물과 전술 채널($Base_{\text{sec}} + 10 + \text{Idx}$)을 배정받습니다.
3. **네트워크 채널 완전 격리 (Strict Network Channel Isolation)**:
   - 광역 대공(`CH 50001`), 광역 백본(`CH 50002`), 대표 비콘(`CH 50003`), GAC 디스패치(`CH 50004`), 및 섹터별 200개 채널 블록($Base_{\text{sec}} = 50001 + S \times 200$, 섹터 관제 $+0$, **섹터 로컬 백본 $+1$**, 전술 채널 $+10 \sim +199$)으로 주파수 스펙트럼을 엄격히 계층 분리하여 채널 혼잡과 패킷 간섭을 원천 차단합니다.
4. **다속성 최적 패드 분배 알고리즘 (Multi-Attribute Allocation)**:
   - GAC는 하드 제약(FREE 상태, 중량 한계, 유효 반경)을 1차 필터링한 후, 맞바람 정렬도($\cos(\Delta \psi)$), 진입거리 최소화, 하중 여유 마진을 다속성 가중 평가하여 관할 내 최적의 착륙 패드를 자동 낙점합니다.
5. **국지 복행(Go-Around) 중재 및 대체 패드 즉시 재배정**:
   - 패드 요동이나 장애물로 복행이 발생하면, GAC가 현장에서 패드를 즉시 격리하고 기체에 로컬 선회(`LOITER`)를 지시하며, 관할 내 다른 가용 패드를 즉각 재배정합니다. 섹터 내 모든 패드가 불가할 때만 상위 Tower ATC로 회항을 이양합니다.
6. **간이 점유 정박 모델 및 이륙 관제**:
   - VTOL 기체는 착륙 패드에 정박 대기(`OCCUPIED`)하며, 이륙 준비 완료 시 GAC에 이륙을 요청합니다. GAC가 이륙 인가(`MSG_GAC_DEPARTURE_CLEARANCE`) 및 패드 개방을 집행하고, 기지 공역 이탈 시 Tower ATC(`CH 50001`)로 상향 핸드오프합니다.
7. **동적 모선/함대 통합 갑판 감시**:
   - 항공모함이나 이동 모선에서 GAC는 선체 중앙 관성 센서(IMU)를 연동하여 전체 비행갑판의 요동을 총괄 감시하며, 위험 시 섹터 단위 진입 동결(`DECK_DANGEROUS`)을 선언합니다.

---

### 1.3 코드 경량화 및 Deprecated 운영 정책 (Code Lightweighting & Deprecation Policy)
1. **사양서 명세 원칙 (Specification-First)**: 프로토콜 패킷 타입명 또는 페이로드 필드가 개정될 경우, 구버전 명칭은 사양서 내에 `[DEPRECATED]` 배지를 부여하고 대체 신규 필드명과 변경 이력을 명시하여 문서상에 보존합니다.
2. **코드베이스 경량화 원칙 (Zero-Fallback)**: CC:Tweaked Lua 분산 컴퓨터 환경의 자원 제약(메모리 절약, 20Hz 실시간 루프 성능 보장)을 준수하기 위해, 코드베이스는 사전 이중 호환(Fallback 래퍼, `payload.new or payload.old` 등)을 일체 작성하지 않고 **최신 표준 필드명/패킷명만을 단일 채택**합니다.
3. **런타임 오류 시 복구 원칙 (송신 노드 즉시 패치)**: 구버전 필드/패킷을 전송하는 미갱신 노드로 인해 수신 측에서 `nil` 인덱싱 등의 런타임 오류가 발생할 경우, 수신 측에 임시 폴백 코드를 추가하지 않고 **구버전 패킷을 송신한 발신 노드의 코드를 최신 사양으로 즉시 패치 및 재배포**하여 전역 일원화를 달성합니다.

---

## 2. 네트워크 채널 및 3대 계층 토폴로지 (Network Channels & Topology)

```mermaid
flowchart TD
    subgraph TIER1["Tier 1: 통합 광역 관제탑 (Master / Tower ATC)"]
        ATC["Tower ATC Node<br/>[CH 50001 대공 / CH 50002 광역 백본]<br/>* 광역 공역 관리 & 섹터별 GAC 핸드오프 지시"]
    end

    subgraph TIER2["Tier 2: 지상 구역 관제사 (Ground Apron Controller, GAC)"]
        GAC1["GAC Sector 01 (기지 알파, Base_sec: 50201)<br/>[CH 50201 관제 / CH 50202 로컬 백본 / CH 50203 비콘]<br/>* 1Hz 섹터 대표 비콘 브로드캐스트 (CH 50003/50203)<br/>* 다속성 패드 최적 분배 & 로컬 복행 중재"]
        GAC2["GAC Sector 02 (항모/모선 갑판, Base_sec: 50401)<br/>[CH 50401 관제 / CH 50402 로컬 백본 / CH 50403 비콘]<br/>* 함선 중앙 IMU 기반 전체 갑판 요동 총괄 감시"]
    end

    subgraph TIER3["Tier 3: 개별 지상/함상 시설물 노드 (Individual Facility Nodes)"]
        PAD1["착륙패드 01 (PAD_01)<br/>[CH 50202 백본 / CH 50211 전술]<br/>* 1:1 전술 스트리밍 & 접지 감지"]
        PAD2["착륙패드 02 (PAD_02)<br/>[CH 50202 백본 / CH 50212 전술]"]
        PAD3["착륙패드 03 (PAD_03)<br/>[CH 50202 백본 / CH 50213 전술]"]
        RWY["활주로 (RWY_01)<br/>[CH 50202 백본 / CH 50220 전술]"]
        DOCK["도킹암 (DOCK_01)<br/>[CH 50202 백본 / CH 50230 전술]"]
    end

    ATC <==>|"CH 50002 (광역 백본)<br/>MSG_ATC_SECTOR_HANDOFF_REQ / ACK"| GAC1
    ATC <==>|"CH 50002 (광역 백본)<br/>MSG_ATC_SECTOR_HANDOFF_REQ / ACK"| GAC2

    GAC1 <==>|"CH 50202 (섹터 로컬 백본)<br/>MSG_ATC_SLOT_ASSIGN / ACK<br/>MSG_ATC_FACILITY_UPDATE"| PAD1
    GAC1 <==>|"CH 50202 (섹터 로컬 백본)"| PAD2
    GAC1 <==>|"CH 50202 (섹터 로컬 백본)"| PAD3
    GAC1 <==>|"CH 50202 (섹터 로컬 백본)"| RWY
    GAC1 <==>|"CH 50202 (섹터 로컬 백본)"| DOCK
```

### 2.1 마스터 채널 할당 표
| 채널 번호 | 채널 식별자 | 송신자 | 수신자 | 전송 주기 | 통신 목적 및 내용 |
| :---: | :---: | :---: | :---: | :---: | :--- |
| **`50001`** | `CH_ATC_COMM` | SAS / Tower ATC | Tower ATC / SAS | 이벤트 | 광역 접근 요청(`MSG_ATC_APPROACH_REQ`), 섹터 핸드오프 인가(`MSG_ATC_HANDOFF_CLEARANCE`), 광역 이탈 관제 |
| **`50002`** | `CH_ATC_FACILITY` | Tower ATC / GAC | GAC / Tower ATC | 이벤트 / 1Hz | 광역 관제탑과 GAC 간 섹터 관제 이양 협상(`MSG_ATC_SECTOR_HANDOFF_REQ/ACK`), 광역 상태 동기화 |
| **`50003`** | `CH_FACILITY_BEACON` | GAC Node (대표) | All (SAS, MFD) | 1Hz | **Sector 0 대표 집약 비콘**: 섹터 ID, 가용 패드 수, 최대 스펙, 국지풍, GAC 관제 채널 |
| **`50004`** | `CH_GAC_DISPATCH` | GAC Node | All (SAS, GCS) | 1Hz | 공용 지상 관제 안내 디스패치 (섹터 목록 및 활성 채널 디렉터리 브로드캐스트) |
| **$Base_{\text{sec}} + 0$** | `CH_GAC_COMM` | SAS / GAC | GAC / SAS | 이벤트 | 섹터 체크인(`MSG_GAC_CHECKIN_REQ`), 최종 패드 배정 인가(`MSG_GAC_APPROACH_CLEARANCE`), 이륙 교신, 로컬 복행 ($Base_{\text{sec}} = 50001 + S \times 200$) |
| **$Base_{\text{sec}} + 1$** | `CH_SECTOR_FACILITY`| GAC / 시설물 노드 | 시설물 노드 / GAC | 이벤트 / 1Hz | **섹터 로컬 백본 격리망**: GAC와 관할 패드 간 슬롯 배정(`MSG_ATC_SLOT_ASSIGN/ACK`), 점유 보고, 리셋 |
| **$Base_{\text{sec}} + 2$** | `CH_SECTOR_BEACON` | GAC Node | All | 1Hz | 개별 섹터 독립 집약 비콘 |
| **$Base_{\text{sec}} + 10 + \text{Idx}$**| `CH_TACTICAL_GUIDANCE`| 시설물 노드 / SAS| SAS / 시설물 노드 | 1Hz(정적) / 20Hz(동적) | 1:1 정밀 유도 스트리밍 (`MSG_FACILITY_STATIC/DYNAMIC_GUIDE`), 접지 통보 (`MSG_TOUCHDOWN_COMPLETE`) |
| **`Base + 5`** | `CH_EXTERNAL_COMM` | SAS / 관제 노드 | 관제 노드 / SAS | 이벤트 | 기체 전용 응답 채널 |

---

## 3. 통신 패킷 상세 규격 (Message Envelope & Payload Specification)

모든 메시지는 표준 공통 Lua 테이블 엔벨로프(`ver`, `domainId`, `seq`, `type`, `time`, `payload`)를 준수하며, Zero-Fallback 원칙에 따라 표준 필드명만을 단일 채택합니다.

### 3.1 광역 섹터 집약 비콘 (`MSG_FACILITY_BEACON`, CH 50003, 1Hz)
GAC 노드가 관할하는 지상 시설물들의 상태를 집약하여 광역 대공으로 송출합니다. 개별 패드는 본 패킷을 송출하지 않습니다.
```lua
{
    ver = "1.9.5",
    domainId = "GAC_ALPHA_01",
    seq = 3001,
    type = "MSG_FACILITY_BEACON",
    time = 1729850000000,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        sectorName = "Alpha Base Central Vertiport",
        sectorType = "VERTIPORT",            -- "VERTIPORT", "AIRPORT", "CARRIER_DECK", "OUTPOST"
        towerAtcChannel = 50001,             -- 상위 Tower ATC 교신 채널
        gacChannel = 50201,                  -- 지상 구역 관제 교신 채널 (Base_sec + 0)
        facilitiesSummary = {
            totalLandingPads = 4,
            freeLandingPads = 3,
            totalRunways = 0,
            freeRunways = 0,
            maxSupportWeight = 40000.0,      -- 수용 가능 최대 이륙 중량 (kg)
            maxSupportRadius = 12.0          -- 수용 가능 최대 패드 반경 (m)
        },
        surfaceWind = {
            speed = 2.4,                     -- 풍속 (m/s)
            direction = 195.0                -- 풍향 (풍상 방위각, deg)
        },
        mobility = "STATIC",                 -- "STATIC" | "DYNAMIC"
        status = "OPERATIONAL"               -- "OPERATIONAL", "DECK_DANGEROUS", "MAINTENANCE"
    }
}
```

---

### 3.2 Tower ATC $\leftrightarrow$ GAC 관제 이양 협상 패킷 (CH 50002)

#### 1. 섹터 이양 요청 (`MSG_ATC_SECTOR_HANDOFF_REQ`, Tower ATC $\to$ GAC)
Tower ATC가 접근 기체의 기본 제원을 전달하며 섹터 수용 가능 여부를 질의합니다.
```lua
{
    ver = "1.9.5",
    domainId = "ATC_TOWER_01",
    seq = 601,
    type = "MSG_ATC_SECTOR_HANDOFF_REQ",
    time = 1729850005000,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        aircraftId = "AIRCRAFT_01",
        airframeType = "VECTORED_VTOL",
        craftWeight = 18500.0,
        craftRadius = 5.2,
        preferredFacilityId = nil,           -- 선택적 특정 패드 요청 (nil 시 GAC가 자동 배정)
        isEmergency = false
    }
}
```

#### 2. 섹터 이양 응답 (`MSG_ATC_SECTOR_HANDOFF_ACK`, GAC $\to$ Tower ATC)
GAC가 섹터 수용 가능 여부를 회신합니다.
```lua
{
    ver = "1.9.5",
    domainId = "GAC_ALPHA_01",
    seq = 3005,
    type = "MSG_ATC_SECTOR_HANDOFF_ACK",
    time = 1729850005100,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        aircraftId = "AIRCRAFT_01",
        status = "ACCEPTED",                 -- "ACCEPTED" | "REJECTED"
        rejectReason = nil,                  -- "SECTOR_ALL_OCCUPIED", "OVERWEIGHT", "DECK_DANGEROUS"
        assignedGacChannel = 50201           -- 기체가 전환할 GAC 관제 채널 (Base_sec + 0)
    }
}
```

---

### 3.3 Tower ATC $\to$ 기체 핸드오프 인가 (`MSG_ATC_HANDOFF_CLEARANCE`, CH 50001 / Base+5)
Tower ATC가 기체에게 관제 이양을 지시하며 전환할 GAC 주파수를 하달합니다.
```lua
{
    ver = "1.9.5",
    domainId = "ATC_TOWER_01",
    seq = 605,
    type = "MSG_ATC_HANDOFF_CLEARANCE",
    time = 1729850005200,
    payload = {
        aircraftId = "AIRCRAFT_01",
        targetSectorId = "BASE_ALPHA_SECTOR_01",
        status = "CLEARED",                  -- "CLEARED" | "DENIED"
        assignedGacChannel = 50201,          -- 핸드오버할 GAC 관제 채널 (Base_sec + 0)
        holdingAltitude = 100.0,             -- 섹터 진입 시 안전 유지 고도 (m)
        reason = nil
    }
}
```

---

### 3.4 SAS $\leftrightarrow$ GAC 섹터 체크인 및 패드 배정 패킷 ($Base_{\text{sec}} + 0$)

#### 1. 섹터 체크인 요청 (`MSG_GAC_CHECKIN_REQ`, SAS $\to$ GAC)
기체가 GAC 주파수로 전환 후 체크인을 수행하며 세부 제원을 보고합니다.
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 710,
    type = "MSG_GAC_CHECKIN_REQ",
    time = 1729850006000,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        aircraftId = "AIRCRAFT_01",
        airframeType = "VECTORED_VTOL",
        craftWeight = 18500.0,
        craftRadius = 5.2,
        currentPos = { x = 1200.0, y = 100.0, z = -750.0 },
        preferredFacilityId = nil,
        isEmergency = false
    }
}
```

#### 2. 최종 접근 인가 (`MSG_GAC_APPROACH_CLEARANCE`, GAC $\to$ SAS)
GAC가 다속성 알고리즘으로 선정한 최적 패드 ID와 전술 유도 채널을 하달합니다.
```lua
{
    ver = "1.9.5",
    domainId = "GAC_ALPHA_01",
    seq = 3012,
    type = "MSG_GAC_APPROACH_CLEARANCE",
    time = 1729850006300,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        aircraftId = "AIRCRAFT_01",
        status = "CLEARED",                  -- "CLEARED" | "HOLD" | "DENIED"
        assignedFacilityId = "PAD_BRAVO_01", -- GAC가 최종 선정한 최적 패드
        assignedTacticalChannel = 50211,     -- 패드 전술 채널 (Base_sec + 10 + PadID)
        touchdownPoint = { x = 1250.0, y = 65.0, z = -820.0 },
        safeDescentRate = 1.0,
        clearanceZoneRadius = 5.0,
        holdingArea = nil,                   -- HOLD 시 선회 중심점 및 고도
        reason = nil
    }
}
```

---

### 3.5 GAC $\leftrightarrow$ 시설물 로컬 백본 패킷 ($Base_{\text{sec}} + 1$)

#### 1. 로컬 슬롯 배정 (`MSG_ATC_SLOT_ASSIGN`, GAC $\to$ Pad Node)
GAC가 낙점된 개별 패드 노드에 슬롯을 배정합니다.
```lua
{
    ver = "1.9.5",
    domainId = "GAC_ALPHA_01",
    seq = 3010,
    type = "MSG_ATC_SLOT_ASSIGN",
    time = 1729850006100,
    payload = {
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        airframeType = "VECTORED_VTOL",
        slotDurationSec = 120,
        tacticalChannel = 50211
    }
}
```

#### 2. 로컬 슬롯 응답 (`MSG_ATC_SLOT_ACK`, Pad Node $\to$ GAC)
패드 노드가 슬롯 배정을 승인합니다.
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",
    seq = 10501,
    type = "MSG_ATC_SLOT_ACK",
    time = 1729850006200,
    payload = {
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        status = "ACCEPTED",
        tacticalChannel = 50211
    }
}
```

#### 3. 로컬 상태 동기화 (`MSG_ATC_FACILITY_UPDATE`, GAC $\leftrightarrow$ Pad Node)
패드가 접지 완료 시 점유를 보고하고, GAC가 패드 개방을 명령할 때 상호 수수합니다.
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",              -- 또는 GAC_ALPHA_01
    seq = 10505,
    type = "MSG_ATC_FACILITY_UPDATE",
    time = 1729850025100,
    payload = {
        facilityId = "PAD_BRAVO_01",
        status = "OCCUPIED",                -- "FREE", "RESERVED", "OCCUPIED", "MAINTENANCE"
        currentCraft = "AIRCRAFT_01"        -- FREE 리셋 시 nil
    }
}
```

---

### 3.6 복행(Go-Around) 및 이탈 보고 패킷

#### 1. 긴급 복행 지시 (`MSG_ABORT_APPROACH`, Pad $\to$ SAS & GAC)
```lua
{
    ver = "1.9.5",
    domainId = "PAD_BRAVO_01",
    seq = 10510,
    type = "MSG_ABORT_APPROACH",
    time = 1729850020000,
    payload = {
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        reason = "DECK_UNSTABLE",            -- "DECK_UNSTABLE", "OBSTACLE_DETECTED", "GAC_ORDER"
        recommendedClimbAltitude = 100.0
    }
}
```

#### 2. 복행 안전 고도 도달 통보 (`MSG_ATC_ABORT_CLEAR`, SAS $\to$ GAC, $Base_{\text{sec}}+0$)
기체가 안전 복행 고도(+30m)에 도달하여 패드 상공을 벗어났음을 GAC에 보고합니다.
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 725,
    type = "MSG_ATC_ABORT_CLEAR",
    time = 1729850024000,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        currentAltitude = 100.0,
        fuelRatio = 0.45
    }
}
```

---

### 3.7 정박 기체 이륙 및 상향 핸드오프 패킷

#### 1. 이륙 요청 (`MSG_GAC_DEPARTURE_REQ`, SAS $\to$ GAC, $Base_{\text{sec}}+0$)
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 750,
    type = "MSG_GAC_DEPARTURE_REQ",
    time = 1729850100000,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        destination = "SECTOR_BRAVO_02"
    }
}
```

#### 2. 이륙 인가 (`MSG_GAC_DEPARTURE_CLEARANCE`, GAC $\to$ SAS, $Base_{\text{sec}}+0$)
```lua
{
    ver = "1.9.5",
    domainId = "GAC_ALPHA_01",
    seq = 3050,
    type = "MSG_GAC_DEPARTURE_CLEARANCE",
    time = 1729850100500,
    payload = {
        sectorId = "BASE_ALPHA_SECTOR_01",
        facilityId = "PAD_BRAVO_01",
        aircraftId = "AIRCRAFT_01",
        status = "CLEARED",
        initialClimbAltitude = 100.0,
        towerAtcChannel = 50001              -- 이탈 후 교신할 Tower ATC 채널
    }
}
```

#### 3. 기지 이탈 확인 및 관제 인수 (`MSG_ATC_ENROUTE_CHECKIN`, SAS $\to$ Tower ATC, CH 50001)
기체가 기지 공역 경계를 통과하며 Tower ATC로 체크인하여 광역 항법 관제로 복귀합니다.
```lua
{
    ver = "1.9.5",
    domainId = "AIRCRAFT_01",
    seq = 760,
    type = "MSG_ATC_ENROUTE_CHECKIN",
    time = 1729850115000,
    payload = {
        aircraftId = "AIRCRAFT_01",
        departedSectorId = "BASE_ALPHA_SECTOR_01",
        currentPos = { x = 1100.0, y = 100.0, z = -600.0 },
        flightPlan = "CRUISE_WAYPOINT_B"
    }
}
```

---

## 4. 유한 상태 기계 및 동작 시퀀스 (FSM & Sequences)

### 4.1 GAC FSM 상태 전이 다이어그램

```mermaid
stateDiagram-v2
    [*] --> SECTOR_IDLE : GAC 시스템 부팅 및 집약 비콘 가동 (1Hz, CH 50003)
    
    SECTOR_IDLE --> HANDOFF_NEGOTIATION : Tower ATC 이양 요청 수신 (MSG_ATC_SECTOR_HANDOFF_REQ)
    HANDOFF_NEGOTIATION --> SECTOR_IDLE : 섹터 만석 거절 회신 (status: REJECTED)
    HANDOFF_NEGOTIATION --> SECTOR_CHECKIN_WAIT : 이양 승인 회신 (status: ACCEPTED, gacChannel 부여)
    
    SECTOR_CHECKIN_WAIT --> ALLOCATING_FACILITY : 기체 체크인 수신 (MSG_GAC_CHECKIN_REQ)
    SECTOR_CHECKIN_WAIT --> SECTOR_IDLE : 60초 체크인 타임아웃 만료
    
    ALLOCATING_FACILITY --> APPROACH_MONITORING : 다속성 최적 패드 낙점 & 패드 슬롯 배정 성공 (MSG_GAC_APPROACH_CLEARANCE)
    ALLOCATING_FACILITY --> SECTOR_HOLDING : 전 패드 점유 시 로컬 LOITER 명령
    
    APPROACH_MONITORING --> BERTHED_OCCUPIED : 패드 점유 보고 수신 (MSG_ATC_FACILITY_UPDATE, OCCUPIED)
    APPROACH_MONITORING --> LOCAL_GO_AROUND : 패드 복행 통보 수신 (MSG_ABORT_APPROACH)
    
    LOCAL_GO_AROUND --> ALLOCATING_FACILITY : 기체 안전고도 도달 보고 수신 (MSG_ATC_ABORT_CLEAR) & 타 FREE 패드 탐색
    LOCAL_GO_AROUND --> TOWER_DIVERT_HANDOFF : 관할 내 대체 패드 부재 시 Tower ATC로 회항 이양
    
    BERTHED_OCCUPIED --> DEPARTURE_HANDOFF : 이륙 요청 수신 (MSG_GAC_DEPARTURE_REQ)
    DEPARTURE_HANDOFF --> SECTOR_IDLE : 기체 이탈 확인 (MSG_ATC_DEPARTURE_COMPLETE) & 패드 FREE 리셋
```

---

### 4.2 정상 진입 및 패드 배정 시퀀스 다이어그램
```mermaid
sequenceDiagram
    autonumber
    participant U as 기체 SAS (Node 04)
    participant T as Tower ATC (CH 50001)
    participant G as GAC (CH 50201)
    participant P as 착륙패드 PAD_01 (CH 50211)

    Note over G: 1Hz 섹터 집약 비콘 송출 (CH 50003, freePads: 3)
    Note over U: 광역 접근 시작 (목표 섹터: BASE_ALPHA)

    U->>T: MSG_ATC_APPROACH_REQ (CH 50001)<br/>[targetSectorId: BASE_ALPHA, craftWeight, radius]
    T->>G: MSG_ATC_SECTOR_HANDOFF_REQ (CH 50002)<br/>[aircraftId, airframeType, craftWeight, radius]
    G-->>T: MSG_ATC_SECTOR_HANDOFF_ACK (CH 50002)<br/>[ACCEPTED, gacChannel: 50201]
    T->>U: MSG_ATC_HANDOFF_CLEARANCE (CH 50001)<br/>[status: CLEARED, gacChannel: 50201]

    Note over U,G: GAC 주파수 (CH 50201) 핸드오버
    U->>G: MSG_GAC_CHECKIN_REQ (CH 50201)<br/>[aircraftId: AIRCRAFT_01, preferredPad: nil]
    Note over G: 다속성 알고리즘 실행 -> PAD_01 낙점
    G->>P: MSG_ATC_SLOT_ASSIGN (CH 50202 로컬 백본)<br/>[aircraftId: AIRCRAFT_01, slotSec: 120]
    P-->>G: MSG_ATC_SLOT_ACK (CH 50202) [ACCEPTED, tacticalChannel: 50211]
    G->>U: MSG_GAC_APPROACH_CLEARANCE (CH 50201)<br/>[assignedFacilityId: PAD_01, tacticalChannel: 50211]

    Note over U,P: 전술 채널 (CH 50211) 핸드오버
    loop 20Hz 동역학 스트리밍
        P->>U: MSG_FACILITY_DYNAMIC_GUIDE (CH 50211) [pos, vel, attitude, deckStatus, landingPermitted]
    end
    Note over U: landingPermitted == true 확인 후 접지
    U->>P: MSG_TOUCHDOWN_COMPLETE (CH 50211)<br/>[facilityId: PAD_01, craftState: GROUND_IDLE]
    P->>G: MSG_ATC_FACILITY_UPDATE (CH 50202) [PAD_01 status: OCCUPIED]
    G->>T: MSG_GAC_SECTOR_STATUS (CH 50002) [freePads: 2]
    Note over P: 패드 점유(OCCUPIED) 및 정박 완료
```

---

### 4.3 국지 복행 및 대체 패드 재배정 시퀀스 다이어그램
```mermaid
sequenceDiagram
    autonumber
    participant U as 기체 SAS (Node 04)
    participant G as GAC (CH 50201)
    participant P1 as 패드 PAD_01 (CH 50211)
    participant P2 as 패드 PAD_02 (CH 50212)

    Note over P1: 최종 하강 중 deckStatus == DANGEROUS 3초 지속
    P1->>U: MSG_ABORT_APPROACH (CH 50211) [reason: DECK_UNSTABLE]
    P1->>G: MSG_ABORT_APPROACH (CH 50202) [reason: DECK_UNSTABLE]
    Note over P1: PAD_01 GO_AROUND 격리

    Note over U: 급상승 복행 기동 (+30m 안전고도 도달)
    U->>G: MSG_ATC_ABORT_CLEAR (CH 50201) [aircraftId: AIRCRAFT_01, alt: 100m]
    G->>P1: MSG_ATC_FACILITY_UPDATE (CH 50202) [PAD_01 status: FREE]
    Note over G: 로컬 LOITER 지시 및 대체 패드 탐색 -> PAD_02 선정
    G->>P2: MSG_ATC_SLOT_ASSIGN (CH 50202) [aircraftId: AIRCRAFT_01, slotSec: 120]
    P2-->>G: MSG_ATC_SLOT_ACK (CH 50202) [ACCEPTED, tacticalChannel: 50212]
    G->>U: MSG_GAC_APPROACH_CLEARANCE (CH 50201)<br/>[assignedFacilityId: PAD_02, tacticalChannel: 50212]
    Note over U,P2: PAD_02 전술 채널 (CH 50212)로 재진입 완료
```

---

### 4.4 정박 기체 이륙 및 Tower ATC 상향 핸드오프 시퀀스 다이어그램
```mermaid
sequenceDiagram
    autonumber
    participant U as 기체 SAS (Node 04)
    participant G as GAC (CH 50201)
    participant P as 패드 PAD_01 (CH 50211)
    participant T as Tower ATC (CH 50001)

    Note over U: 패드 정박 상태 (GROUND_IDLE)에서 임무 준비 완료
    U->>G: MSG_GAC_DEPARTURE_REQ (CH 50201) [facilityId: PAD_01]
    G->>T: MSG_ATC_SECTOR_HANDOFF_REQ (CH 50002) [departureNotice: AIRCRAFT_01]
    T-->>G: MSG_ATC_SECTOR_HANDOFF_ACK (CH 50002) [APPROVED]
    G->>U: MSG_GAC_DEPARTURE_CLEARANCE (CH 50201)<br/>[facilityId: PAD_01, towerChannel: 50001]

    Note over U: 수직 상승 이륙 개시 및 패드 영역 이탈
    U->>G: MSG_ATC_DEPARTURE_COMPLETE (CH 50201)
    G->>P: MSG_ATC_FACILITY_UPDATE (CH 50202) [facilityId: PAD_01, status: FREE]
    Note over P: 패드 IDLE 복귀 (status: FREE)

    Note over U,T: 기지 공역 경계 통과 후 Tower ATC (CH 50001)로 상향 핸드오버
    U->>T: MSG_ATC_ENROUTE_CHECKIN (CH 50001)
    T-->>U: MSG_ATC_ENROUTE_ACK (CH 50001) [순항 인가]
```

---

## 5. 수치해석 및 최적 분배 알고리즘 (Mathematical Modeling & Algorithms)

### 5.1 다속성 최적 시설물 분배 2단계 수치 모델

GAC는 기체의 접근 요청 수신 시 관할 패드 인벤토리 $\mathcal{P} = \{P_1, P_2, \dots, P_n\}$에 대해 2단계 수치 알고리즘을 수행합니다:

#### 1단계: 하드 제약 필터 (Hard Constraint Filter)
후보 패드군 $\mathcal{P}_{valid}$ 추출:
$$\mathcal{P}_{valid} = \left\{ P_i \in \mathcal{P} \;\middle|\; \text{status}(P_i) == \text{"FREE"} \;\land\; W_{max}(P_i) \ge W_{craft} \;\land\; R_{pad}(P_i) \ge R_{craft} \right\}$$
- 기체가 `preferredFacilityId`를 명시했고 해당 패드가 $\mathcal{P}_{valid}$에 포함되어 있다면 즉시 해당 패드로 단독 결정.
- $\mathcal{P}_{valid} == \emptyset$인 경우, GAC는 기체에 `HOLD` 통보 후 로컬 체공 궤도로 유도.

#### 2단계: 소프트 스코어링 함수 (Soft Scoring Function)
$\mathcal{P}_{valid}$의 후보 패드들에 대해 맞바람 정렬도, 진입거리, 하중 여유 마진을 종합 평가:
$$J(P_i) = w_1 \cos(\psi_{wind} - \psi_{approach}(P_i)) - w_2 \frac{\|\vec{p}_{craft} - \vec{p}_{pad}(P_i)\|}{D_{norm}} + w_3 \frac{W_{max}(P_i) - W_{craft}}{W_{craft}}$$
- 가중치 기본값: $w_1 = 0.50$ (풍향 정렬), $w_2 = 0.35$ (접근 거리 최소화), $w_3 = 0.15$ (하중 여유도)
- 정규화 기준 거리: $D_{norm} = 200.0\text{ m}$
- **최종 최적 패드 결정**:
  $$P^* = \arg\max_{P_i \in \mathcal{P}_{valid}} J(P_i)$$

---

### 5.2 동적 함선/모선 갑판 요동 총괄 감시 수치 모델
이동형 해상 플랫폼 상의 GAC는 선체 중앙 IMU 계측값으로 섹터 안전성을 20Hz로 판정합니다:
1. **함선 전체 경사각**:
   $$\theta_{deck\_fleet} = \sqrt{\theta_{pitch}^2 + \theta_{roll}^2} \quad [\text{deg}]$$
2. **섹터 운영 상태 판정**:
   $$\text{sectorStatus} = \begin{cases} \text{"OPERATIONAL"}, & \text{if } \theta_{deck\_fleet} \le 10.0^\circ \text{ and } |v_{y,ship}| \le 2.5\text{ m/s} \\ \text{"DECK_DANGEROUS"}, & \text{otherwise} \end{cases}$$
3. $\text{sectorStatus} == \text{"DECK_DANGEROUS"}$ 지속 시, GAC는 광역 비콘의 `status`를 갱신하고 상위 Tower ATC에 섹터 진입 중단을 통보합니다.

---

### 5.3 페일세이프 및 타임아웃 대응 매트릭스
| 이상 상황 | 감지 조건 | 조치 주체 | 페일세이프 조치 |
| :--- | :--- | :---: | :--- |
| **GAC 체크인 타임아웃** | Tower ATC 핸드오프 인가 후 $60\text{초}$ 내 체크인 무수신 | GAC / Tower | GAC는 섹터 슬롯 예약 취소, Tower ATC는 기체 실종/통신두절 판정 |
| **패드 슬롯 만료** | 패드 접근 인가 후 $120\text{초}$ 동안 접지 미보고 | GAC / Pad | 패드 `GO_AROUND` 격리 후 GAC에 슬롯 만료 보고, 패드 `FREE` 리셋 |
| **섹터 전 패드 만석** | 접근 요청 시 $\mathcal{P}_{valid} == \emptyset$ | GAC | 기체에 로컬 $+30\text{m}$ LOITER 지시, 15초 주기 재탐색, 10회 실패 시 Tower ATC 회항 이양 |
| **동적 갑판 위험 요동** | $\theta_{deck\_fleet} > 10.0^\circ$ 또는 Heave $> 2.5\text{ m/s}$ | GAC | 전 접근 기체에 즉시 `MSG_ABORT_APPROACH` 발령, 대기 선회 지시 |
| **광역 비상 기체 진입** | Tower ATC `MSG_ATC_EMERGENCY_ALERT` 수신 | GAC | 일반 접근 기체 전원 로컬 LOITER/복행 명령, 비상 기체에 최적 패드 즉시 강제 징발 |
