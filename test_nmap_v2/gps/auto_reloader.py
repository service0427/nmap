import json
import os
import sys
import time
import glob
import subprocess
import hashlib
import datetime
import random
# reload_path.py의 고도화된 디코더를 그대로 활용
from reload_path import RouteDecoder

def get_latest_driving_packet(log_dir):
    """현재 로그 디렉토리에서 가장 최신의 v3/global/driving 패킷을 찾음"""
    pattern = os.path.join(log_dir, "*_GET_v3_global_driving.json")
    files = glob.glob(pattern)
    if not files:
        return None
    try:
        # 파일 인덱스(001, 119 등)를 기준으로 내림차순 정렬하여 가장 큰 번호(최신) 선택
        files.sort(key=lambda x: int(os.path.basename(x).split('_')[0]), reverse=True)
        return files[0]
    except:
        return None

def get_content_hash(body_str):
    """데이터 변조 여부 확인을 위한 MD5 해시"""
    return hashlib.md5(str(body_str).encode('utf-8', 'ignore')).hexdigest()

def main(log_dir, device_id):
    # 1. Initialize Session Constraints
    try:
        min_arr = float(os.environ.get("NMAP_MIN_ARRIVAL", 10))
        max_arr = float(os.environ.get("NMAP_MAX_ARRIVAL", 30))
    except:
        min_arr, max_arr = 10, 30
    
    # [V4.0] Fixed Total Target Duration for this session
    total_target_sec = random.randint(int(min_arr * 60), int(max_arr * 60))
    session_start_ts = time.time()
    
    print(f"============================================================")
    print(f"[*] [Auto-Reloader] Dynamic Sync Active: {device_id}")
    print(f"[*] Monitoring: {log_dir}")
    print(f"[*] Session Goal: Arrive within {total_target_sec}s ({total_target_sec/60:.1f} min)")
    print(f"============================================================")
    
    last_data_hash = None
    min_dist = float('inf')  # [V3.2] Track minimum distance to prevent reverse jumps
    
    # [지침] 10초 대기 후 시작 (안내시작 후 안정화 시간)
    time.sleep(10)
    
    while True:
        now_str = datetime.datetime.now().strftime("%H:%M:%S")
        latest_file = get_latest_driving_packet(log_dir)
        
        if not latest_file:
            print(f"[{now_str}] [WAIT] No driving packets in logs. Waiting...")
        else:
            try:
                filename = os.path.basename(latest_file)
                # [V3.1] Retry logic for incomplete JSON files (mitm writing delay)
                data = None
                for _ in range(3):
                    try:
                        with open(latest_file, "r", encoding="utf-8") as f:
                            data = json.load(f)
                        break
                    except json.JSONDecodeError:
                        time.sleep(0.5)
                
                if not data:
                    print(f"[{now_str}] [WARN] {filename} -> Still writing or invalid JSON. Skipping.")
                    time.sleep(2)
                    continue

                res_body = data.get("response", {}).get("body", "")
                
                if not res_body:
                    print(f"[{now_str}] [PASS] {filename} -> Empty response body.")
                else:
                    current_hash = get_content_hash(res_body)
                    
                    if current_hash == last_data_hash:
                        print(f"[{now_str}] [PASS] {filename} -> No change (Hash: {current_hash[:8]})")
                    else:
                        # 신규 데이터 분석
                        coords = RouteDecoder.decode_pbf_path(res_body)
                        dist = RouteDecoder.calculate_distance(coords) if coords else 0
                        
                        if coords and len(coords) >= 5 and dist >= 0.1:
                            # [V3.2] Distance Regression Guard: Prevent jumping back
                            if dist > (min_dist + 0.05):
                                print(f"[{now_str}] [🚫 REGRESSION] {filename} -> Distance increased: {dist:.2f}km > {min_dist:.2f}km. Skipping.")
                                last_data_hash = current_hash
                                continue

                            # Update minimum distance
                            if dist < min_dist:
                                min_dist = dist

                            print(f"[{now_str}] [🚀] UPDATING: {filename} ({dist:.2f} km, {len(coords)} pts)")
                            script_dir = os.path.dirname(os.path.abspath(__file__))
                            
                            # [V4.0] Pass session constraints to reloader
                            env = os.environ.copy()
                            env["NMAP_TARGET_TOTAL_SEC"] = str(total_target_sec)
                            env["NMAP_SESSION_START_TS"] = str(session_start_ts)
                            
                            subprocess.run(["python3", os.path.join(script_dir, "reload_path.py"), latest_file, device_id], 
                                           check=True, env=env)
                            last_data_hash = current_hash
                        else:
                            print(f"[{now_str}] [SKIP] {filename} -> Invalid/Short ({dist:.2f} km).")
                            last_data_hash = current_hash # 루프 방지용 기록
                
            except Exception as e:
                print(f"[{now_str}] [!] Sync Loop Error: {e}")
        
        # [지침] 10초 주기 정밀 체크
        time.sleep(10)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 auto_reloader.py <LOG_DIR> <DEVICE_ID>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
