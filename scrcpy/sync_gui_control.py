#!/usr/bin/env python3
import tkinter as tk
from tkinter import ttk
import subprocess
import threading
from PIL import Image, ImageTk
import io
import time

# --- UI CONFIGURATION (초대형 모드) ---
CANVAS_WIDTH = 600   # 초기 300 -> 2배 확대 (600px)
CANVAS_HEIGHT = 1300 # 초기 650 -> 2배 확대 (1300px)
REFRESH_RATE = 0.4   # 화면 크기가 커졌으므로 갱신 속도를 약간 더 빠르게 조정
# ---------------------------------------

def get_devices():
    try:
        output = subprocess.check_output(["adb", "devices"]).decode("utf-8")
        lines = output.strip().split("\n")[1:]
        return [line.split()[0] for line in lines if line.strip() and "device" in line]
    except:
        return []

def broadcast_cmd(devices, cmd):
    for serial in devices:
        full_cmd = f"adb -s {serial} shell {cmd}"
        subprocess.Popen(full_cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

class VisualSyncApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Ultra-Wide Visual Sync Pad")
        self.root.attributes("-topmost", True)
        
        self.devices = get_devices()
        if not self.devices:
            print("No devices found.")
            return
        
        self.master_serial = self.devices[0]
        self.slaves = self.devices
        
        # UI Setup
        header = tk.Frame(root)
        header.pack(fill=tk.X, pady=5)
        tk.Label(header, text=f"📱 MASTER: {self.master_serial}", font=("Arial", 12, "bold")).pack(side=tk.LEFT, padx=20)
        tk.Label(header, text=f"🔗 SLAVES: {len(self.slaves)}", fg="blue", font=("Arial", 12)).pack(side=tk.RIGHT, padx=20)

        # Main Canvas (Preview)
        self.canvas = tk.Canvas(root, width=CANVAS_WIDTH, height=CANVAS_HEIGHT, bg="black", highlightthickness=3, highlightbackground="#444")
        self.canvas.pack(padx=15, pady=5)
        self.canvas.bind("<Button-1>", self.on_click)
        
        # Bottom Controls
        ctrl_frame = tk.Frame(root)
        ctrl_frame.pack(fill=tk.X, padx=15, pady=15)

        self.entry = tk.Entry(ctrl_frame, font=("Arial", 14), bg="#fafafa")
        self.entry.pack(fill=tk.X, side=tk.TOP, pady=10)
        self.entry.insert(0, "Type text and press Enter...")
        self.entry.bind("<FocusIn>", lambda e: self.entry.delete(0, tk.END) if "Type text" in self.entry.get() else None)
        self.entry.bind("<Return>", lambda e: self.send_text())
        
        btn_frame = tk.Frame(ctrl_frame)
        btn_frame.pack(side=tk.TOP, fill=tk.X)
        
        # 버튼 크기도 화면에 맞춰 확대
        style = {"height": 2, "font": ("Arial", 11, "bold"), "pady": 5}
        tk.Button(btn_frame, text="🏠 HOME", command=lambda: self.send_key(3), bg="#e0e0e0", **style).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=3)
        tk.Button(btn_frame, text="⬅️ BACK", command=lambda: self.send_key(4), bg="#e0e0e0", **style).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=3)
        tk.Button(btn_frame, text="🔄 REFRESH", command=self.update_preview, bg="#90ee90", **style).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=3)

        # Preview Thread
        self.photo = None
        self.last_click = None
        self.running = True
        threading.Thread(target=self.preview_loop, daemon=True).start()

    def update_preview(self):
        try:
            # Capture screen from master (compressed to speed up)
            cmd = ["adb", "-s", self.master_serial, "exec-out", "screencap", "-p"]
            img_data = subprocess.check_output(cmd)
            img = Image.open(io.BytesIO(img_data))
            # Resampling.NEAREST for faster preview on large canvas, or LANCZOS for quality
            img = img.resize((CANVAS_WIDTH, CANVAS_HEIGHT), Image.Resampling.BILINEAR)
            
            self.photo = ImageTk.PhotoImage(img)
            self.canvas.delete("all")
            self.canvas.create_image(0, 0, anchor=tk.NW, image=self.photo)
            
            # Draw red dot for visual feedback
            if self.last_click:
                self.canvas.create_oval(self.last_click[0]-10, self.last_click[1]-10, 
                                        self.last_click[0]+10, self.last_click[1]+10, 
                                        fill="red", outline="white", width=3)
        except:
            pass

    def preview_loop(self):
        while self.running:
            self.update_preview()
            time.sleep(REFRESH_RATE)

    def on_click(self, event):
        # Map CANVAS size to device resolution (e.g., 1080x2400)
        x_mapped = int(event.x * (1080 / CANVAS_WIDTH))
        y_mapped = int(event.y * (2400 / CANVAS_HEIGHT))
        
        self.last_click = (event.x, event.y)
        # Visual feedback update immediately
        self.canvas.create_oval(event.x-10, event.y-10, event.x+10, event.y+10, 
                                fill="red", outline="white", width=3)
                                
        print(f"Sync Tap: {x_mapped}, {y_mapped}")
        broadcast_cmd(self.slaves, f"input tap {x_mapped} {y_mapped}")

    def send_text(self):
        text = self.entry.get()
        if text and "Type text" not in text:
            safe_text = text.replace(" ", "%s")
            broadcast_cmd(self.slaves, f"input text '{safe_text}'")
            self.entry.delete(0, tk.END)

    def send_key(self, code):
        broadcast_cmd(self.slaves, f"input keyevent {code}")

if __name__ == "__main__":
    root = tk.Tk()
    # AnyDesk screen space optimization for ultra-wide
    root.geometry(f"{CANVAS_WIDTH + 50}x{CANVAS_HEIGHT + 200}")
    app = VisualSyncApp(root)
    root.mainloop()
