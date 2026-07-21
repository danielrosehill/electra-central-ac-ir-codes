#set document(title: "Electra Central AC — IR Protocol", author: "Daniel Rosehill")
#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  numbering: "1",
  footer: context [
    #set text(8pt, fill: luma(130))
    Electra Central AC IR Protocol
    #h(1fr)
    #counter(page).display("1 / 1", both: true)
  ],
)
#set text(font: ("Liberation Sans", "DejaVu Sans"), size: 10.5pt)
#set par(justify: true, leading: 0.62em)
#show heading: set block(above: 1.3em, below: 0.7em)
#show heading.where(level: 1): set text(15pt)
#show heading.where(level: 2): set text(12.5pt)
#set heading(numbering: "1.1")
#show raw: set text(font: ("DejaVu Sans Mono", "Liberation Mono"), size: 9pt)

// ---- field palette ----
#let c_power = rgb("#e4572e")
#let c_mode  = rgb("#2b6cb0")
#let c_fan   = rgb("#2f9e44")
#let c_temp  = rgb("#e8a12e")
#let c_fixed = luma(210)

#let chip(col, body) = box(
  fill: col.lighten(72%), stroke: 0.5pt + col, inset: (x: 5pt, y: 2pt),
  radius: 3pt, text(fill: col.darken(20%), weight: 600, body),
)

#let callout(col, title, body) = block(
  width: 100%, fill: col.lighten(85%), stroke: (left: 3pt + col),
  inset: 10pt, radius: 2pt,
  [#text(weight: 700, fill: col.darken(15%), title) \ #body],
)

// ---- title block ----
#block(
  width: 100%, fill: luma(28), inset: 16pt, radius: 4pt,
  [
    #text(fill: white, size: 19pt, weight: 800)[Electra Central AC — IR Protocol]
    #v(2pt)
    #text(fill: luma(190), size: 10.5pt)[
      Reverse-engineered command protocol for a central (ducted) Electra-family
      air conditioner, in Broadlink raw-IR (`b64`) form.
    ]
    #v(6pt)
    #text(fill: luma(150), size: 8.5pt)[
      Rev 2026-07-21 · model unknown · github.com/danielrosehill/electra-central-ac-ir-codes
    ]
  ],
)

#v(4pt)

#callout(c_temp, "At a glance",
  [Manchester bi-phase line coding · 34-bit core payload sent 3× · *no checksum*.
   Power is a single *toggle*; separate state frames carry mode, fan and
   temperature. Because there is no checksum, every command can be *generated* —
   the full 120-code matrix was synthesized from ~7 captured frames.])

= Hardware & capture

The signal was captured with a *Broadlink RM4C mini* IR transceiver in learning
mode (`python-broadlink` `enter_learning()` / `check_data()`), pointed at by the
AC's handheld remote. All codes in this repository are in the Broadlink raw-IR
container: a base64 string beginning `Jg...` (`0x26`), directly usable with
`python-broadlink` `send_data()` or Home Assistant `remote.send_command`
(`command: "b64:…"`).

Broadlink encodes durations in *ticks* of ≈ 32.84 µs. Throughout this document a
duration is given in ticks.

= Physical layer

== Line coding

The frame is *Manchester bi-phase*, not simple pulse-distance. The tell: a
histogram of a capture shows both marks *and* spaces clustering at integer
multiples of a single base unit.

$ "half-bit" T_"h" approx 31.7 "ticks" quad (approx 1.04 "ms") $

Each core bit spans two half-bits (one transition):

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt + luma(200), inset: 7pt, align: (center, center, left),
  table.header([*Bit value*], [*Half-bit levels*], [*Meaning*]),
  [`0`], [mark → space `(1,0)`], [carrier on then off across the bit period],
  [`1`], [space → mark `(0,1)`], [carrier off then on across the bit period],
)

Consecutive equal half-bits merge into one longer mark/space, which is why raw
captures show runs of 1×, 2× and (at boundaries) 3× the base unit.

== Frame structure

#block(fill: luma(245), inset: 10pt, radius: 3pt, [
  `[ leader ] [ 34-bit core ] [ 34-bit core ] [ 34-bit core ] [ lead-out gap ]`
])

- *Leader* — a short mark/space pair (≈ 3 half-bits each) preceding the payload.
- *Core* — the 34-bit payload below, transmitted *three times* back-to-back for
  reliability (all three copies identical).
- *Lead-out* — a long gap (≈ 3333 ticks) closing the transmission.

= The 34-bit core

Bit 0 is the first core bit. Fields occupy fixed positions; every other bit is
constant. #chip(c_power)[power] #h(3pt) #chip(c_mode)[mode] #h(3pt)
#chip(c_fan)[fan] #h(3pt) #chip(c_temp)[temp] #h(3pt)
#box(fill: c_fixed, inset: (x: 5pt, y: 2pt), radius: 3pt, text(weight: 600)[fixed])

// ---- bit strip ----
#let fieldcol(i) = {
  if i == 0 { c_power }
  else if i == 2 or i == 3 { c_mode }
  else if i == 4 or i == 5 { c_fan }
  else if i >= 11 and i <= 14 { c_temp }
  else { c_fixed }
}
#v(4pt)
#align(center, box[
  #grid(
    columns: 34,
    ..range(34).map(i => box(
      width: 15pt, height: 15pt,
      fill: fieldcol(i).lighten(if fieldcol(i) == c_fixed { 30% } else { 55% }),
      stroke: 0.4pt + white,
      align(center + horizon, text(6pt, fill: luma(60))[#i]),
    ))
  )
])
#align(center, text(8pt, fill: luma(120))[core bit index (0–33)])

#v(6pt)

#table(
  columns: (auto, auto, 1fr),
  stroke: 0.5pt + luma(200), inset: 7pt, align: (left, left, left),
  table.header([*Bits*], [*Field*], [*Encoding*]),
  [`0`], chip(c_power)[power flag],
    [`1` = this is the *power-toggle* command · `0` = a state / settings frame],
  [`2–3`], chip(c_mode)[mode],
    [`cool = 01`, `heat = 10` (MSB = bit 2). Other modes untested.],
  [`4–5`], chip(c_fan)[fan],
    [`low = 00`, `med = 01`, `high = 10`, `auto = 11` (MSB = bit 4)],
  [`11–14`], chip(c_temp)[temperature],
    [4-bit value = *°C − 15*, MSB = bit 11 (`16 °C → 0001` … `30 °C → 1111`)],
  [others], box(fill: c_fixed, inset: (x: 5pt, y: 2pt), radius: 3pt)[fixed],
    [Constant framing bits; identical across all captured frames.],
)

#callout(c_power, "Power is a toggle — read this",
  [One code flips the unit on ↔ off (the “on” and “off” captures are
   byte-identical). *State frames do not power the unit on* — sending
   `cool / 22 / high` to an off unit does nothing. To control it: send the power
   toggle to switch on, #emph[then] send state frames for mode/temp/fan.])

= Worked example

The captured frame `cool / high / 20 °C` decodes to this core (bit 0 first):

#align(center, block(fill: luma(245), inset: 9pt, radius: 3pt, [
  `00`#text(fill: c_mode.darken(10%), weight: 700)[`01`]#text(fill: c_fan.darken(10%), weight: 700)[`10`]`00000`#text(fill: c_temp.darken(10%), weight: 700)[`0101`]`0000000000000000010`
]))

#table(
  columns: (auto, auto, 1fr),
  stroke: none, inset: (x: 6pt, y: 3pt), align: (left, left, left),
  [#chip(c_power)[bit 0]], [`0`], [→ a state frame (not the power toggle)],
  [#chip(c_mode)[bits 2–3]], [`01`], [→ *cool*],
  [#chip(c_fan)[bits 4–5]], [`10`], [→ *high*],
  [#chip(c_temp)[bits 11–14]], [`0101` = 5], [→ 5 + 15 = *20 °C*],
)

= Generating any command

With no checksum, a new command is built by rewriting only its field bits in a
template frame and re-encoding to Manchester:

$ "temp bits"(11..14) = "bin"("°C" - 15), quad "fan bits"(4,5) = "code"_"fan", quad "mode bits"(2,3) = "code"_"mode" $

Generated frames were validated two ways: (a) *in-silico* — a generated frame
reproduces the corresponding real capture to within IR jitter (≤ 4 ticks); and
(b) *on the physical AC* — a generated `cool / 25 °C` command drove the unit
correctly.

#callout(c_fan, "Reproduce it yourself",
  [```bash
  python electra_ir.py decode raw_captures/anchor_20.b64   # -> fields
  python electra_ir.py gen cool 22 high                    # -> Broadlink b64
  python electra_ir.py matrix > codes.json                 # rebuild all 120
  ```])

= Methodology (how the map was found)

+ *Capture* a handful of states from the physical remote in Broadlink learn mode.
+ *Decode* the raw pulses; the mark/space multiples-of-one-unit histogram reveals
  Manchester coding → a stable 34-bit core repeated 3×.
+ *Diff* captures: −1 °C vs +1 °C changed one small region → temperature is a
  localized field. Two *known* temperatures (20 and 24) pinned °C − 15, and
  crucially *no other bit moved* → there is no checksum.
+ *Generate & verify* — synthesize codes, validate in-silico and on hardware.
+ *Repeat* for fan (bits 4–5) and mode (bits 2–3), each an isolated field.

Result: ~7 real captures were enough to generate and cross-check a 120-code
matrix (cool + heat × 16–30 °C × 4 fan speeds).

#v(1fr)
#line(length: 100%, stroke: 0.5pt + luma(210))
#text(8pt, fill: luma(130))[
  Codes provided as-is; verify against your own unit. Model number still unknown —
  contributions (model, extra modes, swing, other remote variants) welcome via PR.
  MIT-licensed.
]
