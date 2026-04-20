# Naver Map Auto-Simulation Infrastructure (V2)

## 🚀 V2 Core Architecture

V2는 V1의 물리적 의존성을 탈피하여, 실시간 패킷 검증과 순수 동적 UI 분석을 기반으로 하는 완전 무인 주행 오케스트레이션 시스템입니다.

### 🛠 V2 핵심 원칙
*   **Pure Dynamic UI (NO Hardcoding)**: 모든 UI 조작은 실시간 XML 덤프 분석을 통해 이루어집니다. 고정 좌표(`golden_bounds`)는 절대 사용하지 않으며, 텍스트와 리소스 ID 매칭으로만 작동합니다.
*   **Atomic Packet Verification**: 모든 액션(클릭 등)은 앱이 서버로 보고하는 패킷을 확인한 뒤에만 성공으로 간주하고 전진합니다. (예: `nonloginterm.checkmapservice` 감지 시에만 체크 완료 판정)
*   **Strict Session Isolation**: 모든 주행 데이터, XML 덤프, 스크린샷은 각 세션의 고유 로그 폴더(`logs/{DEV_ID}/{DATE}/{TIME}_{DEST_ID}/`) 내부에 격리 저장됩니다. 공용 폴더(`/tmp`, `screenshot/`) 사용은 엄격히 금지됩니다.
*   **Visual-Structural Audit Pair**: 모든 클릭 시점의 화면은 `.png`와 멀티라인 `.xml` 쌍으로 기록되어 사후 분석을 완벽하게 보장합니다.

### 📂 Directory Structure (V2 Isolation)
*   `test_nmap_v2/`: 핵심 엔진 및 매크로 로직.
*   `test_nmap_v2/logs/{DEV_ID}/.../`:
    *   `execution.log`: 스케줄러 흐름.
    *   `mitm.log`: 세탁된 패킷 로그.
    *   `screenshot/01.{Category}/`: 시점별 스크린샷 및 멀티라인 XML 세트.
