# Home Assistant integration

Drop-in control for this AC via any Broadlink `remote.*` entity. Gives you an
assumed-on toggle plus mode / temperature / fan controls; changing any setting
re-sends the matching IR code while the unit is on.

## Install

1. **Add the Broadlink** to HA (Settings → Devices → Broadlink) so you have a
   `remote.*` entity (e.g. `remote.bedroom_ac`).
2. **Enable packages** in `configuration.yaml` (once):
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
3. **Copy** [`ac_control.yaml`](ac_control.yaml) to `config/packages/`.
4. **Set your remote entity** — edit the two `remote_entity:` lines in the file
   if yours isn't `remote.bedroom_ac`.
5. **Restart** Home Assistant.

You'll get: `input_boolean.ac_on`, `input_select.ac_mode` / `ac_fan`,
`input_number.ac_temp`, and scripts `ac_power_toggle` / `ac_apply_state`.

## Dashboard card

```yaml
type: vertical-stack
cards:
  - type: button
    name: AC Power (toggle)
    icon: mdi:power
    entity: input_boolean.ac_on
    tap_action: { action: perform-action, perform_action: script.ac_power_toggle }
  - type: tile
    entity: input_select.ac_mode
  - type: tile
    entity: input_number.ac_temp
    features: [{ type: numeric-input, style: buttons }]
  - type: tile
    entity: input_select.ac_fan
```

## How power works (important)

The unit's power is a **toggle** (one code flips on↔off) and the mode/temp/fan
frames **do not** power it on. So:

- **Tap Power** to turn the unit on, then adjust mode/temp/fan (those apply live).
- There is **no feedback** from the unit — HA only tracks an *assumed* on/off
  state. If it desyncs (someone used the physical remote), tap Power to re-sync.

## Why not a native `climate` entity / SmartIR?

SmartIR (and HA's climate model generally) assume **discrete on/off** and that
sending a mode command powers the unit on. This unit has neither — power is a
toggle and state frames are inert while off. The helper + script approach above
matches the hardware honestly. A native `climate` entity is possible via a
template-climate or MQTT-climate wrapper (turn-on → send toggle, then state),
but it will always be assumed-state given there's no feedback.

## Regenerating the codes

The package embeds all 120 codes. To rebuild from source:

```bash
python electra_ir.py matrix > codes.json
# then regenerate the package (see repo root)
```
