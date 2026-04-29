import sys
import os

# Add test_nmap_v2/macro to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../test_nmap_v2/macro')))

from ui_clicker import find_element

xml_path = "/home/tech/nmap/test_nmap_v2/logs/R3CN5095QZA/20260422/223154_35840179/screenshot/01.SearchAndNavi/capture_R3CN5095QZA_223220.xml"

queries = [
    "text:서울 강서구 강서로 231 우장산해링턴타워 1, 2층",
    "text:서울 강서구 강서로 231 우장산해링턴타워 1,2층", # Missing space
    "text:서울 강서구 강서로 231 우장산해링턴타워 1,  2층", # Double space
    "text:서울 강서구 강서로 231 우장산해링턴타워 1"
]

print(f"Testing find_element against XML:\n{xml_path}\n")

for q in queries:
    bounds, checked, text = find_element(xml_path, q)
    if bounds:
        print(f"[SUCCESS] Query: '{q}'")
        print(f"          Found Bounds: {bounds}")
        print(f"          Found Text:   '{text}'")
    else:
        print(f"[FAIL]    Query: '{q}' -> Not found")
    print("-" * 60)
