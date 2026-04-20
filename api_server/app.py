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

def generate_spoofed_identity():
    """Generates a fresh set of spoofed identifiers (locked at assignment)"""
    ssaid = secrets.token_hex(8)
    adid = str(uuid.uuid4())
    idfv = str(uuid.uuid4())
    ni = hashlib.md5(ssaid.encode()).hexdigest()
    token = ''.join(secrets.choice("abcdefghijklmnopqrstuvwxyz0123456789") for _ in range(16))
    
    return {
        "ssaid": ssaid,
        "adid": adid,
        "idfv": idfv,
        "ni": ni,
        "token": token
    }

@app.route('/api/v1/request', methods=['GET'])
def request_task():
    device_id = request.args.get('device_id')
    client_ip = request.remote_addr
    
    try:
        db = get_db_connection()
        cursor = db.cursor(dictionary=True)
        
        # 1. Fetch Device Info
        cursor.execute("SELECT * FROM devices WHERE device_id = %s", (device_id,))
        dev_info = cursor.fetchone()
        if not dev_info:
            db.close()
            return jsonify({"status": "error", "message": f"Device {device_id} not registered"}), 404
        
        # Use frida_port directly as the base port
        frida_port = dev_info['seq'] + 30000

        # 2. Fetch VALID Destination (Strictly filter in SQL)
        # Using ONLY existing columns: min_speed, max_speed, min_arrival, max_arrival
        query = """
            SELECT * FROM destinations 
            WHERE status='on' 
              AND min_speed IS NOT NULL 
              AND max_speed IS NOT NULL 
              AND min_arrival IS NOT NULL 
              AND max_arrival IS NOT NULL 
            ORDER BY RAND() LIMIT 1
        """
        cursor.execute(query)
        dest = cursor.fetchone()
        
        if not dest:
            db.close()
            return jsonify({
                "status": "error", 
                "message": "No VALID destinations found. Please check destinations table for status='on' and non-NULL GPS constraints."
            }), 500

        # 3. Generate Identity & Record Task
        spoofed = generate_spoofed_identity()
        insert_query = """INSERT INTO task_log 
                          (device_id, dest_id, dest_name, ip, spoofed_identity, start_time, status) 
                          VALUES (%s, %s, %s, %s, %s, %s, %s)"""
        cursor.execute(insert_query, (
            device_id, dest['dest_id'], dest['name'], client_ip, 
            json.dumps(spoofed), datetime.datetime.now(), "RUNNING"
        ))
        db.commit()
        log_id = cursor.lastrowid

        # 4. Build Response
        task_data = {
            "status": "ok",
            "log_id": log_id,
            "port": frida_port, # Assigned to NMAP_FRIDA_PORT in worker
            "destination": {
                "seq": dest['seq'],
                "id": str(dest['dest_id']),
                "name": dest['name'],
                "address": dest['address'],
                "lat": float(dest['lat']),
                "lng": float(dest['lng']),
                # GPS Constraints (Strictly from DB)
                "min_speed": dest['min_speed'],
                "max_speed": dest['max_speed'],
                "min_arrival": dest['min_arrival'],
                "max_arrival": dest['max_arrival']
            },
            "identity": {
                "original": {
                    "ssaid": dev_info['orig_ssaid'],
                    "adid": dev_info['orig_adid'],
                    "idfv": dev_info['orig_idfv'],
                    "ni": dev_info['orig_ni'],
                    "token": dev_info['orig_token']
                },
                "spoofed": spoofed
            }
        }
        db.close()
        return jsonify(task_data)

    except Exception as e:
        print(f"[!] Request Error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/v1/update_status', methods=['POST'])
def update_status():
    data = request.json
    log_id = data.get('log_id')
    status = data.get('status')
    
    # Optional performance stats (Simplified log schema)
    spoofed_identity = data.get('spoofed_identity')
    
    try:
        db = get_db_connection()
        cursor = db.cursor()
        
        # Build dynamic update query
        update_parts = ["status = %s", "end_time = %s"]
        params = [status, datetime.datetime.now()]
        
        if spoofed_identity is not None:
            update_parts.append("spoofed_identity = %s")
            params.append(json.dumps(spoofed_identity) if isinstance(spoofed_identity, dict) else spoofed_identity)
            
        update_query = f"UPDATE task_log SET {', '.join(update_parts)} WHERE id = %s"
        params.append(log_id)
        
        cursor.execute(update_query, tuple(params))
        db.commit()
        db.close()
        return jsonify({"status": "ok", "message": f"Log ID {log_id} updated successfully"})
    except Exception as e:
        print(f"[!] Update Error: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5003)
