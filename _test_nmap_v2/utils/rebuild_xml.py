import json
import glob
import os
import sys

# 현재 위치 분석
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.dirname(BASE_DIR)
PROJECT_ROOT = os.path.dirname(LIB_DIR)

def build_xml(target_file=None, speed=60.0, dev_id="default", output_path=None):
    if not output_path:
        output_path = f"/tmp/final_1_prefs_{dev_id}.xml"
        
    # [STRICT CHECK] target_file must be provided and exist
    if not target_file or not os.path.exists(target_file):
        print(f"[-] Error: Target JSON file not found: {target_file}")
        sys.exit(1)

    route_json = target_file
    display_name = os.path.splitext(os.path.basename(route_json))[0]
    
    entries = [
        '    <boolean name="noads" value="true" />',
        '    <boolean name="onettimeblock" value="true" />',
        '    <int name="pagbookmark" value="1" />',
        '    <int name="accion" value="0" />',
        f'    <float name="velocidad" value="{speed}" />'
    ]
    
    try:
        with open(route_json, "r", encoding="utf-8") as f:
            coords = json.load(f)
        
        if not coords or len(coords) == 0:
            raise ValueError("Empty coordinates in JSON")
            
        # Standard LAT,LNG order in XML string
        coord_str = ";".join([f"{lat:.7f},{lng:.7f}" for lat, lng in coords]) + ";"
        
        value = f"{display_name}+1+{speed}+0.0+{coord_str}"
        entries.append(f'    <string name="ruta0">{value}</string>')
        
        start_lat, start_lng = coords[0]
        entries.append(f'    <string name="lastloc">Current_Start+{start_lat:.7f},{start_lng:.7f}+15.0</string>')

        xml_content = "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n"
        xml_content += "\n".join(entries)
        xml_content += "\n</map>"
        
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(xml_content)
        print(f"[✓] XML Built at {output_path} for {dev_id}")
    except Exception as e:
        print(f"[-] Error building XML: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Usage: python3 rebuild_xml.py <file> <speed> <dev_id> <output_path>
    if len(sys.argv) < 5:
        print("Usage: python3 rebuild_xml.py <file> <speed> <dev_id> <output_path>")
        sys.exit(1)
        
    arg_file = sys.argv[1]
    arg_speed = float(sys.argv[2])
    arg_dev = sys.argv[3]
    arg_out = sys.argv[4]
    build_xml(arg_file, arg_speed, arg_dev, arg_out)
