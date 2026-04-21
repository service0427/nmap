import os
import json
import glob

def get_file_index(filename):
    try:
        return int(filename.split('_')[0])
    except:
        return -1

def run_distance_threshold_analysis():
    base_path = '/home/tech/nmap/test_nmap_v1/logs'
    dates = ['20260418', '20260419', '20260420']
    target_ids = ['1137533295', '2003102570', '1482572797', '2078247765', '1134187422', '1704402669']
    # 거리 임계값 (km)
    thresholds = [1, 3, 5, 7, 10, 13, 15, 18]
    
    raw_distances = {tid: [] for tid in target_ids}

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
                                        if d > 0:
                                            raw_distances[tid].append(d)
                        except:
                            pass

    # Header
    header = f"{'Target ID':<12} | " + " | ".join([f"D>{t:02}k" for t in thresholds])
    print("Valid Count Comparison by Distance Threshold (Kilometers)")
    print("-" * len(header))
    print(header)
    print("-" * len(header))

    for tid in target_ids:
        counts = []
        for d_km in thresholds:
            count = len([d for d in raw_distances[tid] if d >= d_km])
            counts.append(f"{count:>5}")
        print(f"{tid:<12} | " + " | ".join(counts))

if __name__ == "__main__":
    run_distance_threshold_analysis()
