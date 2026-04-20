# NMAP API 서버 관리 가이드 (PM2)

본 프로젝트의 API 서버(`app.py`)는 **PM2** 프로세스 매니저를 통해 관리됩니다. 이를 통해 서버 크래시 시 자동 재시작, 백그라운드 실행, 로그 모니터링이 가능합니다.

## 1. 기본 서버 제어

| 작업 | 명령어 |
| :--- | :--- |
| **상태 확인** | `pm2 status` |
| **로그 실시간 확인** | `pm2 logs nmap-api` |
| **서버 재시작** | `pm2 restart nmap-api` |
| **서버 정지** | `pm2 stop nmap-api` |
| **서버 시작** | `pm2 start nmap-api` |

## 2. 상세 명령어

### 로그 확인 (가장 많이 사용됨)
최근 로그를 확인하거나 실시간으로 올라오는 로그를 볼 때 사용합니다.
```bash
pm2 logs nmap-api --lines 100
```

### 서버 설정 저장 (재부팅 대비)
서버가 재부팅되었을 때 현재 실행 중인 프로세스 리스트를 자동으로 다시 살리려면 다음 명령어를 실행해야 합니다.
```bash
pm2 save
```

### 프로세스 정보 상세 보기
CPU 사용량, 메모리 점유율, 스크립트 경로 등 상세 정보를 확인합니다.
```bash
pm2 show nmap-api
```

## 3. 서버 수동 등록 방법 (참고용)
만약 프로세스를 삭제 후 다시 등록해야 한다면 아래 명령어를 사용하세요.
```bash
# api_server 폴더로 이동 후 실행
pm2 start app.py --name "nmap-api" --interpreter python3
```

---
*Vibecoding Kit v2.0 - API Infrastructure Management*
