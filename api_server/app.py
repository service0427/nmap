from flask import Flask, request, jsonify
import mysql.connector
import datetime
import os
import uuid
import secrets
import hashlib
import json

app = Flask(__name__)

# MariaDB Config
DB_CONFIG = {
    'host': 'localhost',
    'user': 'nmap',
    'password': 'Tech1324',
    'database': 'nmap'
}

def get_db_connection():
    return mysql.connector.connect(**DB_CONFIG)

def init_db():
    """V3.0: Summary-style daily_tasks and robust allocation schema"""
    try:
        db = get_db_connection()
        cursor = db.cursor()
        
        # 1. task_log Table (Detailed History)
        cursor.execute("SHOW TABLES LIKE 'task_log'")
        if not cursor.fetchone():
            cursor.execute("""
                CREATE TABLE task_log (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    device_id VARCHAR(50),
                    dest_id VARCHAR(20),
                    dest_name VARCHAR(255),
                    ip VARCHAR(45),
                    spoofed_identity TEXT,
                    distance_m INT DEFAULT 0,
                    duration_sec INT DEFAULT 0,
                    start_time DATETIME,
                    end_time DATETIME,
                    status VARCHAR(255)
                )
            """)

        # 2. devices Table
        cursor.execute("SHOW TABLES LIKE 'devices'")
        if not cursor.fetchone():
            cursor.execute("""
                CREATE TABLE devices (
                    seq SMALLINT AUTO_INCREMENT PRIMARY KEY,
                    device_id VARCHAR(50) UNIQUE,
                    current_ip VARCHAR(45),
                    ip_updated_at DATETIME,
                    orig_ssaid VARCHAR(50),
                    orig_adid VARCHAR(50),
                    orig_idfv VARCHAR(50),
                    orig_ni VARCHAR(50),
                    orig_token VARCHAR(50)
                )
            """)

        # 3. destinations Table
        cursor.execute("SHOW COLUMNS FROM destinations")
        cols = [c[0] for c in cursor.fetchall()]
        if "daily_limit" not in cols:
            cursor.execute("ALTER TABLE destinations ADD COLUMN daily_limit INT DEFAULT 5")
        if "created_at" not in cols:
            cursor.execute("ALTER TABLE destinations ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")

        # 4. daily_tasks Table (Summary Style - Recreated for simplicity)
        # Drop old structure if it has 'status' or other obsolete columns
        cursor.execute("SHOW COLUMNS FROM daily_tasks")
        dt_cols = [c[0] for c in cursor.fetchall()]
        if "status" in dt_cols or "actual_dist" in dt_cols:
            print("[*] Recreating daily_tasks to Summary Style...")
            cursor.execute("DROP TABLE daily_tasks")
            
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS daily_tasks (
                dest_id VARCHAR(20),
                work_date DATE,
                success_count INT DEFAULT 0,
                last_assigned_at DATETIME,
                last_success_at DATETIME,
                PRIMARY KEY (dest_id, work_date)
            )
        """)

        # 5. fail_log Table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS fail_log (
                id INT AUTO_INCREMENT PRIMARY KEY,
                log_id INT,
                device_id VARCHAR(50),
                dest_id VARCHAR(20),
                fail_status VARCHAR(255),
                requested_address VARCHAR(255),
                actual_address VARCHAR(255),
                error_msg TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        db.commit()
        db.close()
        print("[✓] V3.0 Database Schema Initialized.")
    except Exception as e:
        print(f"[!] Database Init Error: {e}")

init_db()

def generate_spoofed_identity():
    ssaid = secrets.token_hex(8)
    adid = str(uuid.uuid4())
    idfv = str(uuid.uuid4())
    ni = hashlib.md5(ssaid.encode()).hexdigest()
    token = ''.join(secrets.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(16))
    return {"ssaid": ssaid, "adid": adid, "idfv": idfv, "ni": ni, "token": token}

@app.route('/api/v1/request', methods=['GET'])
def request_task():
    device_id = request.args.get('device_id')
    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)
        
        # 1. Device check
        cursor.execute("SELECT * FROM devices WHERE device_id = %s", (device_id,))
        dev_info = cursor.fetchone()
        if not dev_info:
            db.close(); return jsonify({"status": "error", "message": "Unregistered device"}), 404
        
        frida_port = dev_info['seq'] + 30000

        # 2. Allocation Query (Summary Join + 60s Concurrency Guard)
        # - 오늘 성공 횟수가 일일 제한보다 작아야 함
        # - 마지막 할당된 지 60초가 지났어야 함 (중복 할당 방지)
        query = """
            SELECT d.* 
            FROM destinations d
            LEFT JOIN daily_tasks t ON d.dest_id = t.dest_id AND t.work_date = CURDATE()
            WHERE d.status = 'on'
              AND (t.success_count IS NULL OR t.success_count < d.daily_limit)
              AND (t.last_assigned_at IS NULL OR t.last_assigned_at < NOW() - INTERVAL 60 SECOND)
            ORDER BY RAND() LIMIT 1
        """
        cursor.execute(query)
        dest = cursor.fetchone()
        
        if not dest:
            db.close(); return jsonify({"status": "error", "message": "No available targets"}), 404

        # 3. Process Assignment
        spoofed = generate_spoofed_identity()
        now = datetime.datetime.now()

        # Update Detail Log
        cursor.execute("""
            INSERT INTO task_log (device_id, dest_id, dest_name, ip, spoofed_identity, start_time, status) 
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (device_id, dest['dest_id'], dest['name'], request.remote_addr, json.dumps(spoofed), now, "RUNNING"))
        log_id = cursor.lastrowid

        # Update Summary Table (Upsert Allocation Time)
        cursor.execute("""
            INSERT INTO daily_tasks (dest_id, work_date, last_assigned_at) 
            VALUES (%s, CURDATE(), %s)
            ON DUPLICATE KEY UPDATE last_assigned_at = %s
        """, (dest['dest_id'], now, now))

        db.commit()
        db.close()

        return jsonify({
            "status": "ok", "log_id": log_id, "port": frida_port,
            "destination": {
                "id": str(dest['dest_id']), "name": dest['name'], "address": dest['address'],
                "lat": float(dest['lat']), "lng": float(dest['lng']),
                "min_arrival": dest['min_arrival'], "max_arrival": dest['max_arrival']
            },
            "identity": {
                "original": {
                    "ssaid": dev_info['orig_ssaid'], "adid": dev_info['orig_adid'],
                    "idfv": dev_info['orig_idfv'], "ni": dev_info['orig_ni'], "token": dev_info['orig_token']
                },
                "spoofed": spoofed
            }
        })
    except Exception as e:
        print(f"[!] Request Error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/v1/update_status', methods=['POST'])
def update_status():
    data = request.json
    log_id, device_id, status = data.get('log_id'), data.get('device_id'), data.get('status')
    
    # Optional stats
    dist, duration = data.get('drive_dist'), data.get('drive_time')
    real_ip = data.get('real_ip')
    
    try:
        db = get_db_connection()
        cursor = db.cursor()
        now = datetime.datetime.now()
        
        # 0. Update Device IP
        if device_id and real_ip and real_ip != "Unknown":
            cursor.execute("UPDATE devices SET current_ip=%s, ip_updated_at=%s WHERE device_id=%s", (real_ip, now, device_id))

        # 1. Update Detail Log
        update_parts = ["status = %s", "end_time = %s"]
        params = [status, now]
        if real_ip and real_ip != "Unknown":
            update_parts.append("ip = %s"); params.append(real_ip)
        if dist is not None:
            update_parts.append("distance_m = %s"); params.append(int(dist))
        if duration is not None:
            update_parts.append("duration_sec = %s"); params.append(int(duration))
            
        # Error details if exists
        act_addr, req_addr, err_msg = data.get('actual_address'), data.get('requested_address'), data.get('error_msg')
        if act_addr or err_msg:
            status = f"{status} | Req:{req_addr} | Act:{act_addr} | Msg:{err_msg}"
            params[0] = status

        update_query = f"UPDATE task_log SET {', '.join(update_parts)} WHERE id = %s"
        params.append(log_id)
        cursor.execute(update_query, tuple(params))

        # 2. Update Summary Table (SUCCESS ONLY)
        if "SUCCESS" in status:
            cursor.execute("SELECT dest_id FROM task_log WHERE id = %s", (log_id,))
            row = cursor.fetchone()
            if row:
                dest_id = row[0]
                cursor.execute("""
                    UPDATE daily_tasks 
                    SET success_count = success_count + 1, last_success_at = %s 
                    WHERE dest_id = %s AND work_date = CURDATE()
                """, (now, dest_id))

        # 3. Fail Log if needed
        if "FAIL" in status:
            cursor.execute("SELECT dest_id FROM task_log WHERE id = %s", (log_id,))
            dest_row = cursor.fetchone()
            cursor.execute("""
                INSERT INTO fail_log (log_id, device_id, dest_id, fail_status, requested_address, actual_address, error_msg)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (log_id, device_id, dest_row[0] if dest_row else "Unknown", status, req_addr, act_addr, err_msg))

        db.commit(); db.close()
        return jsonify({"status": "ok"})
    except Exception as e:
        print(f"[!] Update Error: {e}"); return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5003)
