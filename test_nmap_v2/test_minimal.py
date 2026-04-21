import frida
import sys

def on_message(message, data):
    print(message)

def main():
    try:
        device = frida.get_device_manager().add_remote_device("localhost:30001")
        
        # com.nhn.android.nmap 관련 모든 프로세스 찾기
        nmap_procs = []
        for p in device.enumerate_processes():
            if "nmap" in p.name:
                nmap_procs.append(p)
                
        print(f"[*] Found processes: {[(p.pid, p.name) for p in nmap_procs]}")
        
        for p in nmap_procs:
            print(f"[*] Attempting to attach to {p.name} (PID: {p.pid})...")
            try:
                session = device.attach(p.pid)
                script = session.create_script("""
                    try {
                        if (typeof Java !== 'undefined') {
                            send({status: 'ok', pid: Process.id, hasJava: true});
                        } else {
                            send({status: 'no_java', pid: Process.id, hasJava: false});
                        }
                    } catch(e) {
                        send({status: 'error', error: e.message});
                    }
                """)
                def _on_msg(msg, data):
                    if msg['type'] == 'send':
                        print(f"    -> JS Response: {msg['payload']}")
                    else:
                        print(f"    -> JS Error: {msg}")
                script.on('message', _on_msg)
                script.load()
                import time
                time.sleep(1)
                session.detach()
            except Exception as e:
                print(f"    -> Attach failed: {e}")

    except Exception as e:
        print("Error:", e)

if __name__ == '__main__':
    main()
