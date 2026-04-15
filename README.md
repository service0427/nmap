# Naver Map Auto-Simulation Infrastructure

본 레포지토리는 다수의 안드로이드 단말기를 물리적으로 묶어 네이버 지도(Naver Maps) API의 대규모 병렬 가상 주행 및 트래픽 시뮬레이션을 통제하기 위한 통합 인프라 스크립트 모음입니다.

## 🛠 `install.sh` : 신규 단말 초기 구축 스크립트

신규로 구매한 기기(혹은 공장초기화된 기기)를 10대, 100대 등 ADB로 한 번에 연결해두고 `install.sh`를 실행하면 아래 과정을 **전자동으로 일괄 수행**합니다.

1. **필수 앱 설치**:
   - `com.nhn.android.nmap_6.5.2.1` (네이버 지도 특정 버전 강제 고정 - split apk 포함)
   - `com.rosteam.gpsemulator` (GPS 위치 및 속도 오버라이드 유틸리티)
   - `ADBKeyboard.apk` (화면 제어 및 텍스트 자동 입력을 돕기 위한 백그라운드 키보드 레이어)

2. **시스템 인증서 주입 및 Magisk 모듈 구성**:
   - `mitmproxy-ca-cert.crt` 등 루트 폴더(`/install/`)에 위치한 인증서를 해시(Hash) 변환하여 디바이스의 `/data/misc/user/0/cacerts-added/` 폴더에 즉시 밀어넣습니다.
   - 단말기의 `/sdcard/Download` 폴더 안에 Magisk 인증서 시스템 마운트용 모듈 장착 파일들을 대기시킵니다. (최초 1회만 사용자가 Magisk 앱에서 플래싱 후 재부팅하면 영구적으로 시스템 통신 우회를 가능하게 합니다.)

3. **[핵심 보안 우회] 안드로이드 시스템 웹뷰 강제 다운그레이드**:
   - 기기가 자동으로 구글 플레이스토어를 통해 업데이트를 진행해서 **WebView가 v120 단계를 넘어선 최신버전으로 도달하면, `/system` 디렉토리에 장착된 Magisk 우회 인증서를 읽지 않고 자체 APEX 엔진 인증서를 고집하여 크롬(크로미움)의 모든 웹 통신이 블록(net_error -213)되는 현상**이 생깁니다. (로그인 창, 접근 권한 동의 창 백화현상 등)
   - 스크립트가 실행될 때마다 이를 미연에 방지하기 위해 `pm uninstall com.google.android.webview` 명령을 자동으로 때려서 **웹뷰 통신 엔진을 공장 출고 순정 구버전(보통 v111 또는 그 이하)으로 묶어버립니다.**

## 📂 서브 프로젝트 구성
- [`test_nmap_v1`](test_nmap_v1/) : Frida Injector와 MITM_ADDON 기반의 초경량 통신 워싱(Washing) 병렬 구동 환경.
  - **Dynamic UI Clicker**: 해상도 및 앱 UI 변경에 구애받지 않도록 화면 노드(XML) 기반 동적 클릭 로직(`ui_clicker.py`) 적용.
  - **Smart GPS Stall Detection**: 안드로이드 화면 캡처 등 부하가 큰 작업 없이, 네이버 패킷 데이터를 스니핑해 차량(단말기)이 건물이나 주차장에서 정체(Stall) 중인지 스스로 판단 후 경로를 재주입(Hot-Reload)하여 시뮬레이션을 복구하는 기능 내장.
- `vpn_coupang_v1` 등 : 타 목적의 웹 크롤링 및 IP 로테이션 인프라.

---

> **주의사항**
> 테스트베드에 소속된 단말기들은 **절대** 플레이스토어에서 WebView 관련 앱을 개별적으로 업데이트해서는 안 됩니다. 만약 의아하게 동의창이 무한 로딩되거나 통신이 거부된다면 웹뷰 버전과 Magisk AlwaysTrustUserCerts 모듈이 제대로 올라와 있는지 점검하십시오.
