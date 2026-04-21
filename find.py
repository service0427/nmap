import requests
import sys
import json
import re
import urllib3
import mysql.connector

# SSL 경고 무시
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# MariaDB Config (api_server/app.py 설정 기반)
DB_CONFIG = {
    'host': 'localhost',
    'user': 'nmap',
    'password': 'Tech1324',
    'database': 'nmap'
}

class NaverPlaceFinder:
    def __init__(self):
        self.session = requests.Session()
        self.headers = {
            "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "accept-language": "ko-KR,ko;q=0.9",
            "priority": "u=0, i",
            "sec-ch-ua": "\"Google Chrome\";v=\"147\", \"Not.A/Brand\";v=\"8\", \"Chromium\";v=\"147\"",
            "sec-ch-ua-mobile": "?1",
            "sec-ch-ua-platform": "\"Android\"",
            "sec-fetch-dest": "document",
            "sec-fetch-mode": "navigate",
            "sec-fetch-site": "none",
            "sec-fetch-user": "?1",
            "upgrade-insecure-requests": "1",
            "user-agent": "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Mobile Safari/537.36"
        }

    def extract_info(self, html_content):
        pattern_initial = r'window\.__INITIAL_STATE__\s*=\s*({.*?});'
        pattern_apollo = r'window\.__APOLLO_STATE__\s*=\s*({.*?});'
        match = re.search(pattern_initial, html_content, re.DOTALL) or \
                re.search(pattern_apollo, html_content, re.DOTALL)
        
        if not match: return None
        try:
            state = json.loads(match.group(1))
            if "place" in state:
                p = state["place"]["common"]
                return {
                    "id": p.get("id"),
                    "name": p.get("name"),
                    "address": p.get("roadAddress") or p.get("address"),
                    "lng": float(p.get("x") or 0),
                    "lat": float(p.get("y") or 0)
                }
            for key in state.keys():
                if key.startswith("PlaceDetailBase:"):
                    p = state[key]
                    return {
                        "id": p.get("id"),
                        "name": p.get("name"),
                        "address": p.get("roadAddress") or p.get("address"),
                        "lng": float(p.get("coordinate", {}).get("x", 0)),
                        "lat": float(p.get("coordinate", {}).get("y", 0))
                    }
        except: return None
        return None

    def save_to_db(self, info):
        """중복 확인 후 DB에 자동 입력"""
        try:
            db = mysql.connector.connect(**DB_CONFIG)
            cursor = db.cursor()
            
            # dest_id 중복 체크
            cursor.execute("SELECT dest_id FROM destinations WHERE dest_id = %s", (info['id'],))
            if cursor.fetchone():
                print(f"// [DB] ID {info['id']} exists. Skipped.")
            else:
                # 신규 입력 (기본값 설정)
                query = """
                    INSERT INTO destinations 
                    (dest_id, name, address, lat, lng, min_arrival, max_arrival, status)
                    VALUES (%s, %s, %s, %s, %s, 3, 5, 'on')
                """
                cursor.execute(query, (info['id'], info['name'], info['address'], info['lat'], info['lng']))
                db.commit()
                print(f"// [DB] ID {info['id']} inserted successfully.")
            
            db.close()
        except Exception as e:
            print(f"// [DB Error] {e}")

    def find(self, place_id):
        url = f"https://m.place.naver.com/place/{place_id}/home"
        try:
            response = self.session.get(url, headers=self.headers, verify=False, timeout=10)
            response.encoding = 'utf-8'
            if response.status_code == 200:
                info = self.extract_info(response.text)
                if info:
                    # 1. 수동 테스트용 JSON 출력 유지
                    print(json.dumps(info, indent=2, ensure_ascii=False) + ",")
                    # 2. DB 자동 입력 수행
                    self.save_to_db(info)
                else:
                    print(f"// Info not found for ID: {place_id}")
            else:
                print(f"// HTTP Error {response.status_code} for ID: {place_id}")
        except Exception as e:
            print(f"// Connection Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    
    finder = NaverPlaceFinder()
    finder.find(sys.argv[1])
