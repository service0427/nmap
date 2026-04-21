# Naver Map Auto-Simulation Infrastructure (V2/V3)

본 인프라는 수십 대의 안드로이드 단말기를 활용하여 네이버 지도(Naver Maps)의 대규모 병렬 가상 주행 및 트래픽 시뮬레이션을 수행하는 **완전 무인 오케스트레이션 시스템**입니다.

## 🚀 V2/V3 핵심 아키텍처

기존 V1의 물리적 의존성을 탈피하여, 실시간 패킷 검증과 순수 동적 UI 분석을 기반으로 하는 고도화된 엔진을 탑재했습니다.

### 1. Pure Dynamic UI (NO Hardcoding)
- 모든 UI 조작은 실시간 XML 덤프 분석을 통해 이루어집니다. 고정 좌표(`golden_bounds`)를 절대 사용하지 않으며, 텍스트 및 리소스 ID 매칭을 통한 스마트 휴리스틱 클릭 로직을 적용했습니다.
- **Visual-Structural Audit**: 모든 클릭 시점의 화면을 `.png`와 멀티라인 `.xml` 쌍으로 기록하여 완벽한 사후 분석을 보장합니다.

### 2. Intelligent Task API (V3.0)
- **지능형 스케줄링**: 목적지별 1일 작업 한도(`daily_limit`)를 준수하며, 할당 시 `daily_tasks` 요약 테이블을 참조하여 실시간 가용량을 관리합니다.
- **동시성 방어 (60s Guard)**: 동일 목적지가 짧은 시간에 여러 기기에 중복 할당되는 현상을 방어하기 위해 마지막 할당 후 60초 경과 조건을 쿼리 레벨에서 강제합니다.
- **정밀 통계 수집**: 앱이 서버로 보고하는 `trafficjam_log` 패킷을 가로채 실제 주행 거리(m)와 시간(s)을 DB에 정확히 기록합니다.

### 3. Identity Washing & Proxy (Advanced MITM)
- **Exhaustive Washing**: SSAID, ADID, NI, IDFV, TOKEN 등 모든 개인 식별 정보를 Header, Body, URL 전 영역에서 위조된 값으로 실시간 치환합니다.
- **Whitelisting & Logging**: `.naver.com`, `.navercorp.com`, `.naver.net` 도메인을 허용하며, 필터링된 모든 URL은 이유와 함께 `filtered_urls.jsonl`에 기록되어 분석 가능합니다.
- **IP Tracking**: 비행기 모드 토글 후 추출된 **외부 공인 IPv4** 주소를 실시간으로 추적하여 `devices` 테이블에 동기화합니다.

### 4. Sequential Safety Monitor (Auto-Reloader V7.7)
- **3단계 안전 시퀀스**:
  1. **감속**: 목적지 1km 전 도달 시 40km/h로 자동 감속하여 도착 판정 확률 극대화.
  2. **정체 감지**: 30초간 거리 변화가 없을 시 목적지 좌표로 GPS 강제 순간이동.
  3. **강제 종료**: 이동 후에도 정체 시 백키(Back key) 시퀀스를 통해 주행 안내를 안전하게 종료.

## 📂 프로젝트 구조
- `test_nmap_v2/`: V2 핵심 엔진 및 매크로 로직.
- `api_server/`: Flask 기반 통합 제어 서버 (Task 할당 및 상태 관리).
- `mitm/`: mitmproxy 기반 패킷 분석 및 데이터 세탁 모듈.
- `gps/`: GPS 시뮬레이션 및 경로 재주입 유틸리티.

---

## 🛠 `install.sh` : 단말기 초기 구축
ADB로 연결된 모든 기기에 대해 아래 과정을 일괄 수행합니다.
1. **필수 앱 설치**: Naver Map (특정 버전), GPS Emulator, ADBKeyboard.
2. **시스템 인증서 주입**: `mitmproxy` 신뢰할 수 있는 인증서를 시스템 영역에 강제 주입.
3. **웹뷰 다운그레이드**: 통신 보안 우회를 위해 시스템 웹뷰를 순정 구버전으로 고정.

> **주의사항**
> 단말기의 WebView 앱이 업데이트되지 않도록 관리해야 하며, 모든 주행 데이터는 `logs/{DEV_ID}/` 내부에 엄격히 격리 저장됩니다.
