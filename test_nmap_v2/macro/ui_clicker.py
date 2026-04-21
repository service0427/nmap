import subprocess
import xml.etree.ElementTree as ET
from xml.dom import minidom
import random
import time
import os
import sys
import json

def save_multiline_xml(tree_root, file_path):
    """Saves XML tree as a pretty-printed, multiline file"""
    rough_string = ET.tostring(tree_root, 'utf-8')
    reparsed = minidom.parseString(rough_string)
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(reparsed.toprettyxml(indent="  "))

def get_ui_dump_pair(device_id, category_name):
    """Captures Screenshot and Multiline XML strictly into the session log folder"""
    log_dir = os.environ.get("CAPTURE_LOG_DIR")
    if not log_dir or not os.path.exists(log_dir):
        print(f" [!] FATAL ERROR: Session log directory missing")
        return None, None

    target_dir = os.path.join(log_dir, "screenshot", category_name)
    os.makedirs(target_dir, exist_ok=True)
    
    timestamp = time.strftime("%H%M%S")
    xml_file = os.path.join(target_dir, f"capture_{device_id}_{timestamp}.xml")
    png_file = os.path.join(target_dir, f"capture_{device_id}_{timestamp}.png")
    
    try:
        subprocess.run(["adb", "-s", device_id, "shell", "uiautomator", "dump", "/sdcard/ui.xml"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        temp_xml = f"/tmp/raw_{device_id}.xml"
        subprocess.run(["adb", "-s", device_id, "pull", "/sdcard/ui.xml", temp_xml], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        tree = ET.parse(temp_xml)
        save_multiline_xml(tree.getroot(), xml_file)
        os.remove(temp_xml)
        subprocess.run(["adb", "-s", device_id, "shell", "screencap", "-p", "/sdcard/screen.png"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        subprocess.run(["adb", "-s", device_id, "pull", "/sdcard/screen.png", png_file], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        return xml_file, png_file
    except Exception as e:
        print(f" [-] Capture Pair Fail: {e}")
        return None, None

def find_element(xml_file, query):
    """Pure dynamic discovery with Smart Sibling Swap + Flexible Address Matching"""
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        mode, val = query.split(':', 1)
        
        # Build parent map for sibling discovery (Keep original robust logic)
        parent_map = {c: p for p in root.iter() for c in p}
        
        matches = []
        for node in root.iter():
            match = False
            node_text = (node.get('text') or "").strip()
            node_id = (node.get('resource-id') or "")
            node_desc = (node.get('content-desc') or "")
            
            if mode == "text": 
                # [NEW] Flexible matching for addresses (Last 3 words logic)
                if " " in val and len(val.split()) >= 3:
                    target_suffix = " ".join(val.split()[-3:])
                    match = target_suffix in node_text
                else:
                    match = val in node_text
            elif mode == "exact": match = node_text == val
            elif mode == "id": match = node_id == val
            elif mode == "desc": match = val in node_desc
            
            if match:
                bounds_str = node.get('bounds')
                if not bounds_str: continue
                coords = [int(c) for c in bounds_str.replace('][', ',').replace('[', '').replace(']', '').split(',')]
                
                # Scoring logic (Keep original robust scoring)
                score = 0
                x1, y1, x2, y2 = coords
                width, height = x2 - x1, y2 - y1
                area = width * height
                clickable = node.get('clickable', 'false').lower() == 'true'

                if node_text == val: score += 100 
                if clickable: score += 50
                if area > (1080 * 2000 * 0.8): score -= 200
                if area <= 0: score -= 500
                if y1 > 1500: score += 30
                if len(node_text) > len(val) + 10: score -= 30
                if node.get('class') == 'android.view.View' and not clickable: score -= 50
                if 10 < width < 1000 and 10 < height < 500: score += 20
                
                matches.append({
                    'node': node, 'coords': coords, 'checked': node.get('checked', 'false').lower() == 'true',
                    'score': score, 'area': area, 'text': node_text
                })
        
        if not matches: return None, False, None
        
        matches.sort(key=lambda x: (-x['score'], x['area']))
        best = matches[0]
        
        # [SMART HEURISTIC] Checkbox/Label sibling discovery for '필수' (Recovered)
        if "필수" in val:
            node = best['node']
            search_nodes = []
            parent = parent_map.get(node)
            if parent is not None:
                search_nodes.extend(list(parent))
                grandparent = parent_map.get(parent)
                if grandparent is not None:
                    for sibling_parent in grandparent:
                        search_nodes.extend(list(sibling_parent))

            for s in search_nodes:
                s_class = s.get('class', '')
                s_bounds_str = s.get('bounds')
                if not s_bounds_str: continue
                s_coords = [int(c) for c in s_bounds_str.replace('][', ',').replace('[', '').replace(']', '').split(',')]
                sx1, sy1, sx2, sy2 = s_coords
                s_area = (sx2 - sx1) * (sy2 - sy1)
                if ("Image" in s_class or "CheckBox" in s_class) and s_area > 100:
                    bx1, by1, bx2, by2 = best['coords']
                    if max(by1, sy1) < min(by2, sy2): # Vertical overlap
                        if abs(sx1 - bx1) < 500:
                            return s_coords, best['checked'], best['text']
        
        return best['coords'], best['checked'], best['text']
    except Exception as e:
        print(f" [-] find_element Error: {e}")
        return None, False, None

def report_fail(log_id, device_id, status, requested, actual, error):
    """Report failure details to API Server"""
    if not log_id: return
    data = {"log_id": int(log_id), "device_id": device_id, "status": status, "requested_address": requested, "actual_address": actual, "error_msg": error}
    try:
        subprocess.run(["curl", "-s", "-X", "POST", "http://localhost:5003/api/v1/update_status", "-H", "Content-Type: application/json", "-d", json.dumps(data)], stdout=subprocess.DEVNULL)
    except: pass

def click_element(device_id, query, padding=10, category="default"):
    """Executes dynamic click with failure reporting and robust heuristics"""
    log_id = os.environ.get("NMAP_LOG_ID")
    last_actual_text = "Not Found"
    
    for attempt in range(3):
        xml_path, png_path = get_ui_dump_pair(device_id, category)
        if not xml_path: time.sleep(2); continue
            
        bounds, is_checked, actual_text = find_element(xml_path, query)
        if actual_text: last_actual_text = actual_text
        
        # [V2.1 FALLBACK] TermsAgreement Coordinate Fallback (Recovered)
        if not bounds and category == "TermsAgreement" and "동의" in query:
            print(f" [!] Using Coordinate Fallback for TermsAgreement.")
            bounds = [45, 1950, 1035, 2094]; is_checked = False

        if bounds:
            if "필수" in query and is_checked:
                print(f" [✓] {query} already checked. Skipping.")
                return True

            x1, y1, x2, y2 = bounds
            rx_start, rx_end = sorted([x1 + padding, x2 - padding]); ry_start, ry_end = sorted([y1 + padding, y2 - padding])
            if rx_start >= rx_end: rx_end = rx_start + 1
            if ry_start >= ry_end: ry_end = ry_start + 1
            
            target_x = random.randrange(rx_start, rx_end); target_y = random.randrange(ry_start, ry_end)
            subprocess.run(["adb", "-s", device_id, "shell", "input", "tap", str(target_x), str(target_y)])
            print(f" [✓] Clicked {query} at ({target_x}, {target_y})")
            return True
            
        print(f" [-] Element not found [{query}]. XML: {os.path.basename(xml_path)} | Retry {attempt+1}/3...")
        time.sleep(2)
    
    # [NEW] Failure Reporting for Address mismatch
    if "text:" in query:
        requested_addr = query.split("text:", 1)[1]
        print(f" [!] Reporting Mismatch: Req={requested_addr} | Act={last_actual_text}")
        report_fail(log_id, device_id, "FAIL_ADDRESS_MISMATCH", requested_addr, last_actual_text, "Matching failed after 3 retries")

    return False

def chain_click(device_id, queries, padding=10, category="default", delay_range=(1.5, 3.5)):
    """Executes a sequence of clicks with all robust logic (Recovered)"""
    for attempt in range(3):
        xml_path, png_path = get_ui_dump_pair(device_id, category)
        if not xml_path: time.sleep(2); continue
        
        targets = []
        all_found = True
        for query in queries:
            bounds, is_checked, _ = find_element(xml_path, query)
            if not bounds and category == "TermsAgreement" and "동의" in query:
                bounds = [45, 1950, 1035, 2094]; is_checked = False
            
            if bounds:
                targets.append({'query': query, 'bounds': bounds, 'checked': is_checked})
            else:
                all_found = False; break
        
        if not all_found:
            time.sleep(2); continue

        for i, target in enumerate(targets):
            if "필수" in target['query'] and target['checked']: continue
            x1, y1, x2, y2 = target['bounds']
            rx_start, rx_end = sorted([x1+padding, x2-padding]); ry_start, ry_end = sorted([y1+padding, y2-padding])
            tx = random.randrange(rx_start, rx_end if rx_end > rx_start else rx_start+1)
            ty = random.randrange(ry_start, ry_end if ry_end > rx_start else ry_start+1)
            subprocess.run(["adb", "-s", device_id, "shell", "input", "tap", str(tx), str(ty)])
            if i < len(targets) - 1: time.sleep(random.uniform(*delay_range))
        return True
    return False

if __name__ == "__main__":
    if len(sys.argv) < 3: sys.exit(1)
    cat = sys.argv[3] if len(sys.argv) >= 4 else "default"
    click_element(sys.argv[1], sys.argv[2], category=cat)
