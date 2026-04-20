import json
import os
import sys
import time
import gzip
import base64
import subprocess
import math
import random

# [V1 Standard Decoders]
class RouteDecoder:
    @staticmethod
    def calculate_distance(coords):
        if not coords or len(coords) < 2: return 0.0
        total = 0.0
        for i in range(len(coords) - 1):
            lat1, lon1 = coords[i]; lat2, lon2 = coords[i+1]
            R = 6371.0
            dlat = math.radians(lat2 - lat1); dlon = math.radians(lon2 - lon1)
            a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
            c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
            total += R * c
        return total

    @staticmethod
    def decode_zigzag(n): return (n >> 1) ^ (-(n & 1))

    @staticmethod
    def decode_json_path(coords_array):
        if not coords_array or len(coords_array) < 2: return []
        pts = []
        curr_x, curr_y = coords_array[0], coords_array[1]
        pts.append([float(curr_y) / 10000000.0, float(curr_x) / 10000000.0])
        for i in range(2, len(coords_array), 2):
            if i + 1 < len(coords_array):
                curr_x += coords_array[i]; curr_y += coords_array[i+1]
                pts.append([float(curr_y) / 10000000.0, float(curr_x) / 10000000.0])
        return pts

    @classmethod
    def extract_summary(cls, resp_content_raw):
        """Extracts distance(m) and duration(s) from PBF summary (usually field 2 and 3)"""
        try:
            if isinstance(resp_content_raw, str):
                if resp_content_raw.startswith("base64:"):
                    resp_content = base64.b64decode(resp_content_raw.split("base64:")[1])
                else:
                    resp_content = resp_content_raw.encode("latin-1", "replace")
            else:
                resp_content = resp_content_raw
            
            if resp_content and resp_content[:2] == b"\x1f\x8b": 
                resp_content = gzip.decompress(resp_content)
            
            if not resp_content: return 0, 0

            dist, dur = 0, 0
            idx = 0
            limit = min(len(resp_content), 200)
            while idx < limit:
                byte = resp_content[idx]; idx += 1
                tag = byte >> 3
                wire = byte & 0x07
                if wire == 0: # Varint
                    val = 0; shift = 0
                    while True:
                        b = resp_content[idx]; idx += 1
                        val |= (b & 0x7f) << shift
                        shift += 7
                        if not (b & 0x80): break
                    if tag == 2: dist = val
                    elif tag == 3: dur = val
                elif wire == 2: # Length-delimited
                    l = 0; s = 0
                    while True:
                        b = resp_content[idx]; idx += 1
                        l |= (b & 0x7f) << s
                        s += 7
                        if not (b & 0x80): break
                    idx += l
                else: break
            
            return dist, dur
        except: return 0, 0

    @classmethod
    def decode_pbf_path(cls, resp_content_raw):
        try:
            if isinstance(resp_content_raw, str):
                if resp_content_raw.startswith("base64:"):
                    resp_content = base64.b64decode(resp_content_raw.split("base64:")[1])
                else:
                    resp_content = resp_content_raw.encode("latin-1", "replace")
                    if len(resp_content) < 10: 
                        resp_content = resp_content_raw.encode("utf-8", "ignore")
            else:
                resp_content = resp_content_raw
            
            if resp_content and resp_content[:2] == b"\x1f\x8b": 
                resp_content = gzip.decompress(resp_content)
        except Exception as e:
            print(f" [-] PBF Preparation Error: {e}")
            return []
        
        if not resp_content: return []

        for i in range(len(resp_content) - 10):
            if resp_content[i] == 0x0a:
                try:
                    idx = i + 1; length = 0; shift = 0
                    while idx < len(resp_content):
                        b = resp_content[idx]; idx += 1
                        length |= (b & 0x7f) << shift
                        shift += 7
                        if not (b & 0x80): break
                    
                    if 10 < length < 2000000 and idx + length <= len(resp_content):
                        arr = resp_content[idx:idx+length]; idx2 = 0; coords = []
                        while idx2 < len(arr):
                            val = 0; s2 = 0
                            while idx2 < len(arr):
                                b = arr[idx2]; idx2 += 1
                                val |= (b & 0x7f) << s2
                                s2 += 7
                                if not (b & 0x80): break
                            coords.append(cls.decode_zigzag(val))
                        
                        if len(coords) >= 4:
                            lng_sample, lat_sample = coords[0], coords[1]
                            if 1200000000 < lng_sample < 1350000000 and 300000000 < lat_sample < 450000000:
                                return cls.decode_json_path(coords)
                except Exception: pass
        return []

def run_reload(packet_file, device_id):
    if not os.path.exists(packet_file):
        print(f" [-] Error: File {packet_file} not found.")
        return

    print(f"[*] Analyzing packet: {os.path.basename(packet_file)}")
    
    with open(packet_file, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            print(" [-] Error: Invalid JSON format.")
            return

    res_body = data.get("response_body_base64")
    if not res_body:
        res_body = data.get("response", {}).get("body", "")

    if not res_body:
        print(" [-] Error: No response body found in packet.")
        return

    coords = RouteDecoder.decode_pbf_path(res_body)
    if not coords:
        print(" [-] Error: Failed to decode PBF coordinates.")
        return

    # [V4.0 DYNAMIC FEEDBACK CONTROL SPEED LOGIC]
    dist_km = RouteDecoder.calculate_distance(coords)
    
    # 1. Fetch Session Stats & Constraints
    try:
        total_target_sec = float(os.environ.get("NMAP_TARGET_TOTAL_SEC", 1200))
        session_start_ts = float(os.environ.get("NMAP_SESSION_START_TS", time.time()))
        min_spd = float(os.environ.get("NMAP_MIN_SPEED", 40))
        max_spd = float(os.environ.get("NMAP_MAX_SPEED", 80))
    except:
        total_target_sec, session_start_ts, min_spd, max_spd = 1200, time.time(), 40, 80

    # 2. Calculate Remaining Budget
    elapsed_sec = time.time() - session_start_ts
    remaining_sec = total_target_sec - elapsed_sec
    
    # Safety: If we're already overtime or near goal, use 60s minimum for calculation
    safe_remaining_sec = max(60, remaining_sec)
    
    # 3. Calculate required speed: S = D(km) / (T(sec) / 3600)
    required_kmh = dist_km / (safe_remaining_sec / 3600.0)

    # 4. Clamp to Min/Max Speed limits
    target_kmh = max(min_spd, min(max_spd, required_kmh))
    
    # [V4.1] Speed Jitter for FDS Evasion: Add +/- 5km/h randomness
    jitter = random.uniform(-5.0, 5.0)
    final_kmh = max(min_spd, min(max_spd, target_kmh + jitter))
    
    # Final ETA with applied speed
    actual_arrival_mins = (dist_km / final_kmh) * 60.0 if final_kmh > 0 else 0
    
    final_kmh = round(final_kmh, 1)
    
    print(f"[✓] Remaining: {dist_km:.2f} km | Target Time: {total_target_sec:.0f}s | Elapsed: {elapsed_sec:.0f}s")
    print(f"[*] Budget: {remaining_sec:.0f}s left | Base: {target_kmh:.1f} km/h (Jitter: {jitter:+.1f}) -> Applied: {final_kmh} km/h")
    
    temp_route = f"/tmp/hot_route_{device_id}.json"
    with open(temp_route, "w") as f: json.dump(coords, f)
    
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        subprocess.run(["python3", os.path.join(script_dir, "rebuild_xml.py"), temp_route, str(final_kmh), device_id], check=True)
        
        pkg = "com.rosteam.gpsemulator"
        local_xml = f"/tmp/gps_prefs_{device_id}.xml"
        android_tmp = f"/data/local/tmp/hot_gps_{device_id}.xml"
        prefs_path = f"/data/data/{pkg}/shared_prefs/{pkg}_preferences.xml"
        
        subprocess.run(["adb", "-s", device_id, "shell", "am", "force-stop", pkg], check=True)
        subprocess.run(["adb", "-s", device_id, "push", local_xml, android_tmp], check=True, capture_output=True)
        subprocess.run(["adb", "-s", device_id, "shell", f"su -c 'cp {android_tmp} {prefs_path} && chown $(stat -c %u:%g /data/data/{pkg}) {prefs_path} && chmod 660 {prefs_path} && rm {android_tmp}'"], check=True)
        
        speed_mps = round(final_kmh / 3.6, 6)
        print(f"[*] Injecting Memory Command: {speed_mps} m/s")
        
        subprocess.run(["adb", "-s", device_id, "shell", "su -c", 
            f"am start-foreground-service -n {pkg}/.servicex2484 "
            f"-a ACTION_START_CONTINUOUS "
            f"--es uy.digitools.RUTA 'ruta0' "
            f"--ef velocidad {speed_mps} "
            f"--ei loopMode 0"], check=True)

        log_id = os.environ.get("NMAP_LOG_ID")
        if log_id:
            try:
                report_data = {
                    "log_id": log_id, 
                    "applied_speed": final_kmh, 
                    "status": "DRIVING",
                    "remaining_dist": dist_km,
                    "target_duration": total_target_sec
                }
                subprocess.run(["curl", "-s", "-X", "POST", "http://localhost:5003/api/v1/update_status", 
                                "-H", "Content-Type: application/json", 
                                "-d", json.dumps(report_data)], 
                               stdout=subprocess.DEVNULL)
            except: pass
        
        print(f"============================================================")
        print(f" [✓] MEMORY-BASED HOT RELOAD COMPLETE: {device_id}")
        print(f"============================================================")
        
    finally:
        if os.path.exists(temp_route): os.remove(temp_route)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 reload_path.py <JSON_PACKET_FILE> <DEVICE_ID>")
        sys.exit(1)
    run_reload(sys.argv[1], sys.argv[2])
