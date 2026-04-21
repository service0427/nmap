import os
import json
import glob

def get_file_index(filename):
    try:
        return int(filename.split('_')[0])
    except:
        return -1

def run_threshold_comparison():
    base_path = '/home/tech/nmap/test_nmap_v1/logs'
    dates = ['20260418', '20260419', '20260420']
    target_ids = ['1137533295', '2003102570', '1482572797', '2078247765', '1134187422', '1704402669']
    thresholds = [3, 5, 6, 7, 8, 9, 10]
    
    # Raw data collection
    raw_data = {tid: [] for tid in target_ids}

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
                                        t = float(inner.get('13', 0)) / 60
                                        if t > 0:
                                            raw_data[tid].append(t)
                        except:
                            pass

    # Header
    header = f"{'Target ID':<12} | " + " | ".join([f"T>{t:02}m" for t in thresholds])
    print("Valid Count Comparison by Threshold (Minutes)")
    print("-" * len(header))
    print(header)
    print("-" * len(header))

    for tid in target_ids:
        counts = []
        for t_min in thresholds:
            count = len([t for t in raw_data[tid] if t >= t_min])
            counts.append(f"{count:>5}")
        print(f"{tid:<12} | " + " | ".join(counts))

if __name__ == "__main__":
    run_threshold_comparison()
