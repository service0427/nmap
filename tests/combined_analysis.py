import os
import json
import glob

def get_file_index(filename):
    try:
        return int(filename.split('_')[0])
    except:
        return -1

def run_combined_analysis():
    base_path = '/home/tech/nmap/test_nmap_v1/logs'
    dates = ['20260418', '20260419', '20260420']
    target_ids = ['1137533295', '2003102570', '1482572797', '2078247765', '1134187422', '1704402669']
    
    # 결합 임계값 쌍 (거리 km, 시간 min)
    threshold_pairs = [
        (3, 3),   # 최소 기본 주행
        (5, 5),   # 유효 진입
        (7, 6),   # 중거리
        (10, 8),  # 고품질 주행
        (13, 10), # 장거리 고품질
        (15, 12)  # 초장거리
    ]
    
    raw_sessions = {tid: [] for tid in target_ids}

    for date in dates:
        for tid in target_ids:
            search_pattern = os.path.join(base_path, '*', date, f'*-{tid}')
            matching_dirs = glob.glob(search_pattern)

            for log_dir in matching_dirs:
                files = os.listdir(log_dir)
                files.sort(key=get_file_index)
                routeend_idx = -1
                for f in files:
                    if 'routeend' in f:
                        routeend_idx = get_file_index(f)
                        break
                if routeend_idx == -1: continue

                for f in files:
                    if 'trafficjam_log' in f and get_file_index(f) > routeend_idx:
                        try:
                            with open(os.path.join(log_dir, f), 'r') as jf:
                                data = json.load(jf)
                                body_pb = data.get('request', {}).get('body_protobuf', {})
                                for key in body_pb:
                                    inner = body_pb[key]
                                    if isinstance(inner, dict):
                                        d = float(inner.get('12', 0)) / 1000
                                        t = float(inner.get('13', 0)) / 60
                                        if d > 0 and t > 0:
                                            raw_sessions[tid].append((d, t))
                        except:
                            pass

    # Header
    col_headers = [f"D>{p[0]}k&T>{p[1]}m" for p in threshold_pairs]
    header = f"{'Target ID':<12} | " + " | ".join(col_headers)
    print("Combined Threshold Analysis (Distance AND Time)")
    print("-" * len(header))
    print(header)
    print("-" * len(header))

    for tid in target_ids:
        counts = []
        for d_min, t_min in threshold_pairs:
            count = len([s for s in raw_sessions[tid] if s[0] >= d_min and s[1] >= t_min])
            counts.append(f"{count:^11}")
        print(f"{tid:<12} | " + " | ".join(counts))

if __name__ == "__main__":
    run_combined_analysis()
