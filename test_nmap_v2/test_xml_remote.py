import subprocess
import xml.etree.ElementTree as ET
import re
import sys

DEVICE_ID = "R3CN10BZ7PD"

def get_xml_dump(device_id):
    try:
        # 1. 디바이스에서 XML 생성
        dump_cmd = f"adb -s {device_id} shell uiautomator dump /data/local/tmp/window_dump.xml"
        subprocess.run(dump_cmd, shell=True, check=True, capture_output=True)
        
        # 2. 로컬로 풀링
        pull_cmd = f"adb -s {device_id} pull /data/local/tmp/window_dump.xml window_dump.xml"
        subprocess.run(pull_cmd, shell=True, check=True, capture_output=True)
        
        return "window_dump.xml"
    except Exception as e:
        print(f"[-] XML 덤프 실패: {e}")
        return None

def parse_bounds(bounds_str):
    """ '[x1,y1][x2,y2]' 형식의 문자열을 파싱해서 중심 x, y 반환 """
    m = re.match(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', bounds_str)
    if m:
        x1, y1, x2, y2 = map(int, m.groups())
        return (x1 + x2) // 2, (y1 + y2) // 2
    return -1, -1

def extract_navigation_info(xml_file):
    if not xml_file: return
    
    tree = ET.parse(xml_file)
    root = tree.getroot()
    
    stats = {'distance': '...', 'duration': '...', 'quit_x': -1, 'quit_y': -1, 'found_quit': False}
    
    # 순회하면서 리소스 ID 매칭 (V2 아키텍처 'Pure Dynamic UI' 규칙 적용)
    for node in root.iter('node'):
        res_id = node.get('resource-id', '')
        
        if res_id == 'com.nhn.android.nmap:id/distance':
            stats['distance'] = node.get('text', '')
            
        elif res_id == 'com.nhn.android.nmap:id/duration':
            stats['duration'] = node.get('text', '')
            
        elif res_id == 'com.nhn.android.nmap:id/v_quit':
            bounds = node.get('bounds', '')
            cx, cy = parse_bounds(bounds)
            stats['quit_x'] = cx
            stats['quit_y'] = cy
            stats['found_quit'] = True

    print(f"[+] 거리: {stats['distance']}, 시간: {stats['duration']}")
    if stats['found_quit']:
        print(f"[+] 종료(v_quit) 버튼 좌표: ({stats['quit_x']}, {stats['quit_y']})")
    else:
        print(f"[-] 종료(v_quit) 버튼을 찾을 수 없습니다.")

def main():
    print(f"[*] {DEVICE_ID} 단말기에서 실시간 XML 덤프 중... (앱 충돌 없음)")
    xml_path = get_xml_dump(DEVICE_ID)
    extract_navigation_info(xml_path)

if __name__ == "__main__":
    main()
