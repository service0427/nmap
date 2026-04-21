import os
import json
import argparse
import glob

def get_file_index(filename):
    try:
        return int(filename.split('_')[0])
    except (ValueError, IndexError):
        return -1

def analyze(target_date, target_id):
    base_path = '/home/tech/nmap/test_nmap_v1/logs'
    search_pattern = os.path.join(base_path, '*', target_date, f'*-{target_id}')
    matching_dirs = glob.glob(search_pattern)

    if not matching_dirs:
        print(f"No directories found for date: {target_date}, id: {target_id}")
        return

    results = []
    for log_dir in matching_dirs:
        path_parts = log_dir.split(os.sep)
        device_id = path_parts[-3] if len(path_parts) >= 3 else "Unknown"

        files = os.listdir(log_dir)
        files.sort(key=get_file_index)

        routeend_index = -1
        for f in files:
            if 'routeend' in f:
                routeend_index = get_file_index(f)
                break
        
        if routeend_index == -1:
            continue

        for f in files:
            if 'trafficjam_log' in f:
                idx = get_file_index(f)
                if idx > routeend_index:
                    file_path = os.path.join(log_dir, f)
                    try:
                        with open(file_path, 'r') as jf:
                            data = json.load(jf)
                            body_pb = data.get('request', {}).get('body_protobuf', {})
                            for key in body_pb:
                                inner = body_pb[key]
                                if isinstance(inner, dict):
                                    val12 = inner.get('12')
                                    val13 = inner.get('13')
                                    if val12 is not None and val13 is not None:
                                        dist_km = float(val12) / 1000
                                        time_min = float(val13) / 60
                                        results.append({
                                            'device': device_id,
                                            'dist': dist_km,
                                            'time': time_min
                                        })
                    except:
                        pass

    if not results:
        print("No valid trafficjam logs found after routeend.")
        return

    # Print Header
    print(f"{'No':<4} {'DeviceID':<15} {'Distance':>10} {'Time':>10}")
    print("-" * 45)

    total_dist = 0
    total_time = 0
    for i, res in enumerate(results, 1):
        total_dist += res['dist']
        total_time += res['time']
        print(f"{i:02d}   {res['device']:<15} {res['dist']:>8.2f}km {res['time']:>8.1f}min")

    # Summary
    count = len(results)
    avg_dist = total_dist / count
    avg_time = total_time / count
    # Speed = km / (min / 60) = km/h
    avg_speed = total_dist / (total_time / 60) if total_time > 0 else 0

    print("-" * 45)
    print(f"Total Count: {count}")
    print(f"Average Distance : {avg_dist:>8.2f} km")
    print(f"Average Time     : {avg_time:>8.1f} min")
    print(f"Average Speed    : {avg_speed:>8.2f} km/h")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('date', help='Date in YYYYMMDD format')
    parser.add_argument('id', help='Target ID')
    args = parser.parse_args()

    analyze(args.date, args.id)
