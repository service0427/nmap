import frida
import sys
import time

# Target Configuration
DEVICE_ID = "R3CN10BZ7PD"
FRIDA_PORT = 30001
PACKAGE_NAME = "com.nhn.android.nmap"

def on_message(message, data):
    if message['type'] == 'send':
        print(f"[*] {message['payload']}")
    elif message['type'] == 'error':
        print(f"[-] JS Error: {message['description']}")
    else:
        # console.log 등 일반 로그 출력
        if 'payload' in message:
            print(f"[LOG] {message['payload']}")

def find_target_pid(device):
    try:
        apps = device.enumerate_applications()
        for app in apps:
            if app.identifier == PACKAGE_NAME and app.pid != 0:
                return app.pid
        processes = device.enumerate_processes()
        for process in processes:
            if process.name == PACKAGE_NAME:
                return process.pid
    except Exception as e:
        print(f"[-] PID 탐색 오류: {e}")
    return None

def main():
    try:
        print(f"[*] Connecting to {DEVICE_ID} via localhost:{FRIDA_PORT}...")
        device_manager = frida.get_device_manager()
        device = device_manager.add_remote_device(f"localhost:{FRIDA_PORT}")
        
        target_pid = find_target_pid(device)
        if not target_pid:
            print(f"[-] {PACKAGE_NAME} 프로세스를 찾을 수 없습니다. 앱이 실행 중인지 확인하세요.")
            return

        print(f"[*] PID {target_pid} (네이버지도) 에 In-Memory 접속 중...")
        session = device.attach(target_pid)
        
        # [V2 Architecture] In-Memory Scan Logic
        hook_code = """
        console.log("[JS] V2 In-Memory Scan Plugin Loaded (Zero-Load Mode)");
        
        function runV2Scan() {
            var checkCount = 0;
            var checkTimer = setInterval(function() {
                checkCount++;
                var javaExists = (typeof Java !== 'undefined');
                var javaAvailable = javaExists ? Java.available : false;
                console.log("[DEBUG] Java Check #" + checkCount + ": Exists=" + javaExists + ", Available=" + javaAvailable);
                
                if (javaExists && javaAvailable) {
                    clearInterval(checkTimer);
                    startIntervalScan();
                }
                if (checkCount >= 20) {
                    console.log("[!] 20회 시도 후에도 Java를 찾지 못했습니다. 앱이 완전히 로드되었는지 확인하세요.");
                    clearInterval(checkTimer);
                }
            }, 1000);
        }

        function startIntervalScan() {
            console.log("[✓] Java Bridge Active. Starting 10s Interval Scan...");
            setInterval(function() {
                Java.perform(function() {
                    try {
                        var ActivityThread = Java.use('android.app.ActivityThread');
                        var app = ActivityThread.currentApplication();
                        if (!app) return;

                        var res = app.getResources();
                        var pkg = 'com.nhn.android.nmap';
                        var stats = { d: '...', t: '...', s: '0', qx: -1, qy: -1, found: false };
                        
                        var View = Java.use('android.view.View');
                        var Rect = Java.use('android.graphics.Rect');
                        
                        var idDistance = res.getIdentifier('distance', 'id', pkg);
                        var idDuration = res.getIdentifier('duration', 'id', pkg);
                        var idQuit = res.getIdentifier('v_quit', 'id', pkg);

                        Java.choose('android.widget.TextView', {
                            onMatch: function(i) {
                                try {
                                    var id = i.getId();
                                    if (id === idDistance) stats.d = i.getText().toString();
                                    if (id === idDuration) stats.t = i.getText().toString();
                                    if (id === idQuit) {
                                        var v = Java.cast(i, View);
                                        var rect = Rect.$new();
                                        v.getGlobalVisibleRect(rect);
                                        stats.qx = rect.centerX();
                                        stats.qy = rect.centerY();
                                        stats.found = true;
                                    }
                                } catch(e) {}
                            },
                            onComplete: function() {
                                Java.choose('android.location.Location', {
                                    onMatch: function(loc) {
                                        try {
                                            var vel = loc.getSpeed();
                                            if (vel > 0) { 
                                                stats.s = Math.floor(vel * 3.6).toString(); 
                                                return 'stop';
                                            }
                                        } catch(e) {}
                                    },
                                    onComplete: function() {
                                        if (stats.d !== '...' || stats.found) {
                                            send("[TELEMETRY]|" + stats.s + "|" + stats.d + "|" + stats.t + "|" + stats.found + "|" + stats.qx + "|" + stats.qy);
                                        }
                                    }
                                });
                            }
                        });
                    } catch(e) {}
                });
            }, 10000);
        }

        runV2Scan();
        """
        
        script = session.create_script(hook_code)
        script.on('message', on_message)
        script.load()
        
        print("[*] V2 모니터링 활성화됨. 상태 점검 중...")
        sys.stdin.read()
        
    except KeyboardInterrupt:
        print("[*] 사용자 중단 요청.")
    except Exception as e:
        print(f"[-] 오류 발생: {e}")

if __name__ == "__main__":
    main()
