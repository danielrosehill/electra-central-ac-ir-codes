# Electra / Tadiran Central AC — IR Codes + Reverse-Engineering Methodology

Broadlink-format IR codes for a **central (ducted) Electra-family air conditioner**
— the kind installed as a whole-home/mini-central unit in Israel and driven by a
generic wall/handheld IR remote rather than a per-room split's own remote.

The exact model is **unknown** (central units usually have no accessible remote/
indoor-unit model sticker). This will be updated if the model is identified. The
protocol below was recovered purely by capturing and decoding the remote's IR.

> **Why this exists:** these units are common but their remotes match **no**
> ready-made database (SmartIR's Tadiran code sets 1340–1346/1560 all failed
> here). Rather than hand-capture dozens of button states, the protocol was
> decoded from a handful of samples, which showed it has **no checksum** — so
> the entire command matrix can be *generated* in software. The codes and the
> method are both published here.

## Contents

| File | What |
|------|------|
| [`protocol.pdf`](protocol.pdf) | **Illustrated protocol spec** (color-coded bit map, field tables, worked example). Source: `protocol.typ` (Typst). |
| `codes.json` | Full generated code set: power toggle + 120 state frames (cool/heat × 16–30 °C × 4 fan speeds), plus the decoded protocol spec. |
| `electra_ir.py` | Self-contained codec: **decode** a capture, **generate** any state, or **regenerate the whole matrix**. |
| `raw_captures/*.b64` | The real learned captures the whole thing was derived from (for reproducibility). |

> 📄 **Start with [`protocol.pdf`](protocol.pdf)** for the human-readable bit-field map. The section below is the same spec in text form.

## The protocol

- **Carrier format:** Broadlink `b64:` raw IR (the strings work directly with
  `python-broadlink` `send_data`, or Home Assistant `remote.send_command`).
- **Line coding:** Manchester bi-phase, half-bit ≈ **31.7 Broadlink ticks**.
- **Frame:** short leader → **34-bit core** payload → repeated **3×** back-to-back → lead-out gap.
- **No checksum.** Changing one setting flips only that field's bits; everything else is byte-stable.

### Core bit fields (index 0 = first core bit)

| Bits | Field | Encoding |
|------|-------|----------|
| 0 | power-toggle flag | `1` = the **power toggle** command; `0` = a state/settings frame |
| 2–3 | mode | `cool=01`, `heat=10` (MSB = bit 2) |
| 4–5 | fan | `low=00`, `med=01`, `high=10`, `auto=11` (MSB = bit 4) |
| 11–14 | temperature | value = **°C − 15**, 4-bit MSB = bit 11 (`16 °C=0001` … `30 °C=1111`) |

Only `cool`/`heat` and the four fan speeds were captured; other modes (dry,
fan-only, auto) likely reuse the mode field with other 2-bit values.

### Power behaviour (important)

Power is a **single toggle**: one code flips the unit on↔off (the "off" and
"on" captures are byte-identical). **State frames do not power the unit on** —
sending `cool/22/high` to an off unit does nothing. To control it: send the
**power toggle** to turn on, *then* send state frames to set mode/temp/fan.

## Usage

```bash
# Decode a capture into fields
python electra_ir.py decode raw_captures/anchor_20.b64
#   -> {"mode":"cool","fan":"high","temp":20, ...}

# Generate any state as a Broadlink base64 code
python electra_ir.py gen cool 22 high
python electra_ir.py gen heat 24 low

# Regenerate the entire matrix
python electra_ir.py matrix > codes.json
```

Send a code (example with `python-broadlink`):

```python
import broadlink, base64
dev = broadlink.discover()[0]; dev.auth()
dev.send_data(base64.b64decode(open_code))   # b64 string decoded to bytes
```

### Home Assistant

`remote.send_command` with a Broadlink `remote.*` entity:

```yaml
service: remote.send_command
target: { entity_id: remote.bedroom_ac }
data:   { command: "b64:JgDEAF9f..." }   # any code from codes.json
```

Because power is a toggle and state frames don't self-power the unit, a clean HA
setup is: a **power-toggle** button/script, plus `input_number` (temp) +
`input_select` (mode, fan) helpers whose changes fire the matching state code
via an automation. (This is how the author drives it; a native `climate` entity
would need a template-climate wrapper since SmartIR assumes discrete on/off.)

## How it was reverse-engineered (methodology)

1. **Capture** a few states with a Broadlink RM4C mini in IR-learn mode
   (`python-broadlink` `enter_learning()` / `check_data()`).
2. **Decode** the raw Broadlink pulses. A histogram showed marks *and* spaces
   clustering at multiples of one base unit → **Manchester**, not simple
   pulse-distance. Manchester-decoding gave a stable 34-bit core repeated 3×.
3. **Diff adjacent captures.** −1 °C vs +1 °C differed in exactly one small
   region → temperature is a localized field. Two *known* temperatures (20, 24)
   pinned the mapping: **field value = °C − 15**, and crucially **no other bit
   moved → no checksum**.
4. **Generate & verify.** With no checksum, any state can be synthesized by
   rewriting its field. Generated codes were validated (a) in-silico — a
   generated frame reproduces a real capture within IR jitter — and (b) on the
   physical AC.
5. **Repeat** for fan (bits 4–5) and mode (bits 2–3), each an isolated field.

The upshot: **~7 real captures** were enough to generate a **120-code** matrix,
all cross-checked against the originals.

## Contributing

If you have one of these units: PRs welcome to add the **model number**, more
modes (dry/fan-only/auto), swing, or captures from a different remote variant.
Drop raw `.b64` captures in `raw_captures/` and note the state each represents.

## License

MIT — see `LICENSE`. Codes provided as-is; verify against your own unit.
