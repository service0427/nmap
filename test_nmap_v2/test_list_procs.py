import frida
device = frida.get_device_manager().add_remote_device("localhost:30001")
for p in device.enumerate_processes():
    if "nmap" in p.name:
        print(f"PID: {p.pid}, Name: {p.name}")
