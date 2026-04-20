import subprocess
import xml.etree.ElementTree as ET
from xml.dom import minidom
import random
import time
import os
import sys

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
        print(f" [!] FATAL ERROR: Session log directory missing: {log_dir}")
        sys.exit(1) # Stop immediately if isolation is violated

    # Build path: {log_dir}/screenshot/{category_name}
    target_dir = os.path.join(log_dir, "screenshot", category_name)
    os.makedirs(target_dir, exist_ok=True)
    
    timestamp = time.strftime("%H%M%S")
    xml_file = os.path.join(target_dir, f"capture_{device_id}_{timestamp}.xml")
    png_file = os.path.join(target_dir, f"capture_{device_id}_{timestamp}.png")
    
    try:
        # 1. Dump UI (Temporary on device)
        subprocess.run(["adb", "-s", device_id, "shell", "uiautomator", "dump", "/sdcard/ui.xml"], 
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        # 2. Pull and save as multiline
        temp_xml = f"/tmp/raw_{device_id}.xml"
        subprocess.run(["adb", "-s", device_id, "pull", "/sdcard/ui.xml", temp_xml], 
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        
        # [AUDIT QUALITY] Save as pretty-printed multiline XML
        tree = ET.parse(temp_xml)
        save_multiline_xml(tree.getroot(), xml_file)
        os.remove(temp_xml)
        
        # 3. ScreenCap
        subprocess.run(["adb", "-s", device_id, "shell", "screencap", "-p", "/sdcard/screen.png"], 
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        subprocess.run(["adb", "-s", device_id, "pull", "/sdcard/screen.png", png_file], 
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        
        return xml_file, png_file
    except Exception as e:
        print(f" [-] Capture Pair Fail: {e}")
        return None, None

def find_element(xml_file, query):
    """Pure dynamic discovery based on query (text, exact, id, desc) with smart ranking and sibling discovery"""
    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        mode, val = query.split(':', 1)
        
        # Build parent map for sibling discovery
        parent_map = {c: p for p in root.iter() for c in p}
        
        matches = []
        for node in root.iter():
            match = False
            node_text = (node.get('text') or "")
            node_id = (node.get('resource-id') or "")
            node_desc = (node.get('content-desc') or "")
            
            if mode == "text": match = val in node_text
            elif mode == "exact": match = node_text == val
            elif mode == "id": match = node_id == val
            elif mode == "desc": match = val in node_desc
            
            if match:
                bounds_str = node.get('bounds')
                if not bounds_str: continue
                coords = [int(c) for c in bounds_str.replace('][', ',').replace('[', '').replace(']', '').split(',')]
                
                # Scoring logic
                score = 0
                x1, y1, x2, y2 = coords
                width, height = x2 - x1, y2 - y1
                area = width * height
                clickable = node.get('clickable', 'false').lower() == 'true'

                if node_text == val: score += 100 # Exact match priority
                if clickable: score += 50
                
                # Penalize massive containers (e.g. WebView, full screen frames)
                if area > (1080 * 2000 * 0.8): score -= 200
                if area <= 0: score -= 500
                
                # Reward bottom position (often where action buttons are)
                if y1 > 1500: score += 30
                
                # Penalize if it's a long sentence and we just want a specific word
                if len(node_text) > len(val) + 10: score -= 30
                
                # Penalize non-clickable Views that just happen to have text
                if node.get('class') == 'android.view.View' and not clickable: score -= 50

                # Prefer nodes with reasonable size
                if 10 < width < 1000 and 10 < height < 500: score += 20
                
                matches.append({
                    'node': node,
                    'coords': coords,
                    'checked': node.get('checked', 'false').lower() == 'true',
                    'score': score,
                    'area': area
                })
        
        if not matches: return None, False
        
        # Sort by score descending, then by area ascending (more specific node first)
        matches.sort(key=lambda x: (-x['score'], x['area']))
        best = matches[0]
        
        # [SMART HEURISTIC] Checkbox/Label sibling discovery for '필수'
        if "필수" in val:
            node = best['node']
            search_nodes = []
            
            # 1. Immediate siblings
            parent = parent_map.get(node)
            if parent is not None:
                search_nodes.extend(list(parent))
                # 2. Parent's siblings' children (handle nested layouts)
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
                
                # If sibling is an Image or CheckBox and has a reasonable area
                if ("Image" in s_class or "CheckBox" in s_class) and s_area > 100:
                    # Vertical alignment check (overlap)
                    bx1, by1, bx2, by2 = best['coords']
                    if max(by1, sy1) < min(by2, sy2): # Vertical overlap
                        # Horizontal proximity check
                        if abs(sx1 - bx1) < 500:
                            print(f" [!] Smart Sibling Swap: {best['coords']} -> {s_coords} ({s_class})")
                            return s_coords, best['checked']
        
        return best['coords'], best['checked']
    except Exception as e:
        print(f" [-] find_element Error: {e}")
        return None, False

def click_element(device_id, query, padding=10, category="default"):
    """Executes pure dynamic click with session-isolated logging"""
    for attempt in range(3):
        xml_path, png_path = get_ui_dump_pair(device_id, category)
        if not xml_path: time.sleep(2); continue
            
        bounds, is_checked = find_element(xml_path, query)
        
        # [V2.1 FALLBACK] Handle WebView 'Agree' Button failure on specific devices
        if not bounds and category == "TermsAgreement" and "동의" in query:
            print(f" [!] Element [{query}] missing in XML. Using Coordinate Fallback for TermsAgreement.")
            bounds = [45, 1950, 1035, 2094] # Gold Standard bounds for NMAP V2 Agreement Button
            is_checked = False

        if bounds:
            # Special check for checkboxes
            if "필수" in query and is_checked:
                print(f" [✓] {query} already checked. Skipping.")
                return True

            x1, y1, x2, y2 = bounds
            # Ensure valid range for randrange
            rx_start, rx_end = sorted([x1 + padding, x2 - padding])
            ry_start, ry_end = sorted([y1 + padding, y2 - padding])
            if rx_start >= rx_end: rx_end = rx_start + 1
            if ry_start >= ry_end: ry_end = ry_start + 1
            
            target_x = random.randrange(rx_start, rx_end)
            target_y = random.randrange(ry_start, ry_end)
            
            subprocess.run(["adb", "-s", device_id, "shell", "input", "tap", str(target_x), str(target_y)])
            print(f" [✓] Clicked {query} at ({target_x}, {target_y})")
            return True
            
        print(f" [-] Element not found [{query}]. XML: {os.path.basename(xml_path)} | Retry {attempt+1}/3...")
        time.sleep(2)
    return False

def chain_click(device_id, queries, padding=10, category="default", delay_range=(1.5, 3.5)):
    """Executes a sequence of clicks with a retry-protected UI capture"""
    for attempt in range(3):
        xml_path, png_path = get_ui_dump_pair(device_id, category)
        if not xml_path:
            print(f" [-] Chain Attempt {attempt+1}/3: UI Capture Failed. Retrying...")
            time.sleep(2)
            continue
            
        print(f" [*] Chain Discovery Started (Attempt {attempt+1}/3) on {os.path.basename(xml_path)}")
        
        # 1. Collect all target coordinates first from this stable XML
        targets = []
        all_found = True
        for query in queries:
            bounds, is_checked = find_element(xml_path, query)
            
            # Fallback for '동의'
            if not bounds and category == "TermsAgreement" and "동의" in query:
                print(f" [!] Chain: Element [{query}] missing. Using Fallback.")
                bounds = [45, 1950, 1035, 2094]
                is_checked = False

            if bounds:
                targets.append({'query': query, 'bounds': bounds, 'checked': is_checked})
            else:
                print(f" [-] Chain Step: Element [{query}] not found in this dump.")
                all_found = False
                break
        
        # 2. If any element was not found, retry the whole capture
        if not all_found:
            print(f" [!] Elements missing in current UI dump. Retrying capture ({attempt+1}/3)...")
            time.sleep(2)
            continue

        # 3. All elements found! Execute the sequence
        for i, target in enumerate(targets):
            if "필수" in target['query'] and target['checked']:
                print(f" [✓] {target['query']} already checked. Skipping.")
                continue

            x1, y1, x2, y2 = target['bounds']
            rx_start, rx_end = sorted([x1 + padding, x2 - padding])
            ry_start, ry_end = sorted([y1 + padding, y2 - padding])
            if rx_start >= rx_end: rx_end = rx_start + 1
            if ry_start >= ry_end: ry_end = ry_start + 1
            
            target_x = random.randrange(rx_start, rx_end)
            target_y = random.randrange(ry_start, ry_end)
            
            subprocess.run(["adb", "-s", device_id, "shell", "input", "tap", str(target_x), str(target_y)])
            print(f" [✓] Chain Step {i+1}: Clicked {target['query']} at ({target_x}, {target_y})")
            
            if i < len(targets) - 1:
                wait_time = random.uniform(*delay_range)
                print(f"     > Waiting {wait_time:.2f}s for UI update...")
                time.sleep(wait_time)
                
        return True # Success
            
    print(f" [!] Chain Click FAILED after 3 capture attempts.")
    return False

if __name__ == "__main__":
    if len(sys.argv) < 3: sys.exit(1)
    cat = sys.argv[3] if len(sys.argv) >= 4 else "default"
    click_element(sys.argv[1], sys.argv[2], category=cat)
