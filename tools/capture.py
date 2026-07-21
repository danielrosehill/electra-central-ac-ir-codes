#!/usr/bin/env python3
"""
Capture IR frames from your AC's handheld remote using a Broadlink device.

Use this if your unit is a different variant and you want to verify or extend
the code set (e.g. add dry/fan-only/auto modes, swing, or a different remote).

    pip install broadlink
    python tools/capture.py 10.0.20.144 cool_22_low     # <blaster-ip> <label>

Point the remote at the Broadlink and press the button when prompted. The raw
Broadlink base64 is printed and saved to raw_captures/<label>.b64.

Decode what you captured:   python electra_ir.py decode raw_captures/<label>.b64
"""
import base64, os, sys, time

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    ip, label = sys.argv[1], sys.argv[2]
    import broadlink
    devs = broadlink.discover(discover_ip_address=ip, timeout=8)
    if not devs:
        print(f"No Broadlink found at {ip}"); sys.exit(1)
    d = devs[0]; d.auth()
    print(f"Device: {d.model} @ {d.host[0]} (unlocked={not d.is_locked})")
    d.enter_learning()
    print(f">>> Press the remote button for '{label}' now (pointing at the Broadlink) <<<")
    code = None
    for _ in range(25):                     # ~50 s window
        try:
            pkt = d.check_data()
            if pkt:
                code = pkt; break
        except Exception:
            pass
        time.sleep(2)
    if not code:
        print("No code captured (timed out)."); sys.exit(2)
    b64 = base64.b64encode(code).decode()
    os.makedirs("raw_captures", exist_ok=True)
    path = os.path.join("raw_captures", f"{label}.b64")
    open(path, "w").write(b64)
    print(f"Captured {len(code)} bytes -> {path}")
    print(b64)

if __name__ == "__main__":
    main()
