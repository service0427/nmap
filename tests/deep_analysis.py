import os
import json
import glob

def get_file_index(filename):
    try:
        return int(filename.split('_')[0])
    except:
        return -1

def run_deep_analysis():
    base_path = '/home/tech/nmap/test_nmap_v1/logs'
    dates = ['20260418', '20260419', '20260420']
    target_ids = ['1482572797', '1134187422', '1704402669', '1137533295', '2003102570', '2078247765']
    
    # 성과 데이터 매핑
    scores = {
        '1137533295': 0.067043,
        '1482572797': 0.002443,
        '1704402669': -0.000752,
        '2003102570': 0.002796,
        '2078247765': 0.000369,
        '1134187422': 0.0  # 미기재시 0
    }

    stats = {tid: {'dist': 0.0, 'time': 0.0, 'count': 0} for tid in target_ids}

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
                                        if d > 0 and t >= 3:
                                            stats[tid]['dist'] += d
                                            stats[tid]['time'] += t
                                            stats[tid]['count'] += 1
                        except:
                            pass

    # 결과 출력
    print(f"{'Target ID':<12} | {'Score':>10} | {'Total Dist':>12} | {'Total Time':>12} | {'Count':>6} | {'Avg Dist':>8} | {'Avg Time':>8}")
    print("-" * 95)
    
    # 성과순(Score) 정렬 출력
    sorted_ids = sorted(target_ids, key=lambda x: scores.get(x, 0), reverse=True)
    
    for tid in sorted_ids:
        s = stats[tid]
        score = scores.get(tid, 0)
        avg_dist = s['dist'] / s['count'] if s['count'] > 0 else 0
        avg_time = s['time'] / s['count'] if s['count'] > 0 else 0
        
        print(f"{tid:<12} | {score:>10.6f} | {s['dist']:>10.2f} km | {s['time']:>10.1f} min | {s['count']:>6} | {avg_dist:>8.2f} | {avg_time:>8.1f}")

if __name__ == "__main__":
    run_deep_analysis()
