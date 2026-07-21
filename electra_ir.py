#!/usr/bin/env python3
"""
Electra / Tadiran central-AC IR codec (Broadlink RM4-format).

Reverse-engineered from a generic wall/handheld IR remote driving a central
(ducted) Electra-family air conditioner, captured with a Broadlink RM4C mini.

Protocol (see README for the full write-up):
  - Manchester bi-phase, half-bit ~= 31.7 Broadlink ticks.
  - 34-bit core payload, transmitted 3x back-to-back, framed by a short leader
    and a lead-out gap.
  - NO checksum. Each field occupies fixed bit positions and nothing else moves.

Core bit fields (index 0 = first core bit):
  bit 0      power-toggle flag  (1 = the power TOGGLE command; 0 = a state frame)
  bits 2-3   mode   cool=01, heat=10          (MSB = bit 2)
  bits 4-5   fan    low=00 med=01 high=10 auto=11 (MSB = bit 4)
  bits 11-14 temp   value = (Celsius - 15)     (MSB = bit 11; 16C=0001 .. 30C=1111)

Power is a single TOGGLE (same code flips on<->off). State frames set
mode/temp/fan but do NOT power the unit on - it must already be running.

Usage:
  python electra_ir.py decode raw_captures/anchor_20.b64
  python electra_ir.py gen cool 22 high         # -> Broadlink base64
  python electra_ir.py matrix > codes.json      # regenerate the full set
"""
import base64, json, sys, re

BASE = 31.7          # Broadlink ticks per Manchester half-bit
CORE_BITS = 34
REPEATS = 3
LEADOUT = 3333       # trailing gap (ticks)
FAN  = {"low": 0, "med": 1, "high": 2, "auto": 3}
MODE = {"cool": 1, "heat": 2}


def parse(b64):
    raw = base64.b64decode(b64)
    n = raw[2] | (raw[3] << 8)
    body = raw[4:4 + n]
    p, i = [], 0
    while i < len(body):
        if body[i] == 0:
            p.append((body[i + 1] << 8) | body[i + 2]); i += 3
        else:
            p.append(body[i]); i += 1
    return p


def to_samples(pulses):
    """Pulse list -> half-bit level stream (drops the final large gap)."""
    s = []
    for i, v in enumerate([v for v in pulses if v < 300]):
        s += [1 if i % 2 == 0 else 0] * max(1, round(v / BASE))
    return s


def rle(samples):
    out, i = [], 0
    while i < len(samples):
        j = i
        while j < len(samples) and samples[j] == samples[i]:
            j += 1
        out.append(round((j - i) * BASE)); i = j
    return out


def encode(pulses):
    body = b""
    for v in pulses:
        body += bytes([v]) if v < 256 else bytes([0, (v >> 8) & 0xFF, v & 0xFF])
    n = len(body)
    return base64.b64encode(bytes([0x26, 0, n & 0xFF, (n >> 8) & 0xFF]) + body).decode()


def core(b64):
    """Decode one 34-bit core payload from a Broadlink capture."""
    s = to_samples(parse(b64))
    n = len(s) - (len(s) % 2)
    bits = ""
    for i in range(0, n, 2):
        pair = (s[i], s[i + 1])
        bits += "0" if pair == (1, 0) else "1" if pair == (0, 1) else "?"
    segs = [x for x in re.split(r"\?+", bits) if len(x) >= CORE_BITS - 2]
    return segs[0]


def decode_fields(b64):
    c = core(b64)
    return {
        "core": c,
        "is_power_toggle": c[0] == "1",
        "mode": next((k for k, v in MODE.items() if v == int(c[2:4], 2)), "?"),
        "fan":  next((k for k, v in FAN.items()  if v == int(c[4:6], 2)), "?"),
        "temp": int(c[11:15], 2) + 15,
    }


def _set(samples, pos, bit, r):
    idx = r * 74 + 6 + 2 * pos            # per-repeat leader = 6 half-bits; 2 per core bit
    samples[idx], samples[idx + 1] = (0, 1) if bit else (1, 0)


def generate(template_samples, mode, celsius, fan):
    """Build a state frame from a template capture by rewriting the fields."""
    s = template_samples[:]
    tv, fv, mv = celsius - 15, FAN[fan], MODE[mode]
    for r in range(REPEATS):
        for pos, b in zip((2, 3),           [(mv >> k) & 1 for k in (1, 0)]):       _set(s, pos, b, r)
        for pos, b in zip((4, 5),           [(fv >> k) & 1 for k in (1, 0)]):       _set(s, pos, b, r)
        for pos, b in zip((11, 12, 13, 14), [(tv >> k) & 1 for k in (3, 2, 1, 0)]): _set(s, pos, b, r)
    return encode(rle(s) + [LEADOUT])


TEMPLATE_B64 = None  # set from raw_captures/anchor_20.b64 at runtime


def _template():
    import os
    path = os.path.join(os.path.dirname(__file__), "raw_captures", "anchor_20.b64")
    return to_samples(parse(open(path).read().strip()))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd == "decode":
        print(json.dumps(decode_fields(open(sys.argv[2]).read().strip()), indent=2))
    elif cmd == "gen":
        mode, temp, fan = sys.argv[2], int(sys.argv[3]), sys.argv[4]
        print(generate(_template(), mode, temp, fan))
    elif cmd == "matrix":
        t = _template()
        out = {"power_toggle": open(__import__("os").path.join(
            __import__("os").path.dirname(__file__), "raw_captures", "power_toggle.b64")).read().strip()}
        for m in MODE:
            for c in range(16, 31):
                for f in FAN:
                    out[f"{m}_{c}_{f}"] = generate(t, m, c, f)
        print(json.dumps(out, indent=1))
    else:
        print(__doc__)
