# Dual-Board Directional Speaker — Implementation Plan

**Date:** 2026-11-13  
**Workspace:** `E:\LUIS\IPP\fpga`  
**Confirmed geometry:** coplanar, same facing, side-by-side along x; board B
offset **+5 mm in x and +5 mm in y** (half of the 10 mm lattice pitch); gap
minimized. Boards are phase-locked with primary `MISC_D` → secondary `MISC_A`.

> **Measured-geometry correction (2026-11-13).**  The Gerber/pick-place data
> give a **10.5 mm** pitch, a **157.5 mm** element span and a 185.09 ×
> 168.40 mm PCB, not 10 mm / 150 mm.  The boards are butted at a
> **36.75 mm** element-centre seam with a **5.25 mm** y offset (the acrylic
> fixture in `E:\LUIS\IPP\mounting_mechanics`).  The grating direction is
> therefore **54.75°**, not 59°.  The pre-measurement 5 mm / 10 mm / 59°
> numbers below are superseded where they conflict; the host code uses the
> measured values.

**Goal:** a narrow broadside main beam (narrower than ±20° is good) and no
grating-lobe side leak above 60°. The 5.25 mm half-pitch offset cancels the
four axial 54.75° grating lobes while the broadside field adds in phase.

**Current assets**

| Path | State |
|---|---|
| `E:\LUIS\IPP\fpga\primary` | Git repo. Quartus 25.1 primary build with per-channel duty amplitude weighting. Fit 5,628 / 6,272 LE (90 %). `QuadrupleBuffer_primary.jic` committed. |
| `E:\LUIS\IPP\fpga\reference\secondary-original` | Original Quartus 13.0 secondary project (copied from SonicSurface): 10.24 MHz, **32 phase bins**, 230.4 kBaud, `MISC_A` sync input, reversed board-select polarity, secondary correction table, **no music_player / no duty weighting**. Reference only. |
| `E:\LUIS\IPP\fpga\secondary` | Git repo, baseline derived from `fpga/primary` (5.12 MHz / 16 phases / 38.4 kBaud / duty weighting / music_player). Commit `ec42fc7`. Role changes pending. |
| `E:\LUIS\IPP\demo` | Git repo. Single-board host, amplitude frames, Hann/Gaussian tapers, phase optimizer, calibration. **No dual-board support yet.** |

### Critical finding: the old secondary is a different generation

The primary is **5.12 MHz / 16 phase bins / 38.4 kBaud / duty weighting / music_player**.
The old SonicSurface secondary is **10.24 MHz / 32 phase bins / 230.4 kBaud / no
music_player**. Both produce a 40 kHz carrier (32 × 8 clk8 at 10.24 MHz = 256
clk8 = 25 µs; 16 × 8 clk8 at 5.12 MHz = 128 clk8 = 25 µs), but their protocols
and phase resolutions are incompatible for a combined array.

**Do not port the old secondary piecemeal.** Build the secondary from the
current `fpga/primary` project and apply only the secondary role differences
(MISC_A sync input, secondary correction table, reversed board-select
polarity). The old secondary project is kept as
`fpga/reference/secondary-original` only for the MISC_A sync net, pin map and
secondary table.

---

## 1. Acceptance criteria

1. Both boards emit phase-locked 40 kHz carriers from the same sync source.
2. The 54.75° lobes (az 0/90/180/270) are at least **20 dB below the main beam**
   in the far field (target **25–30 dB** after trim).
3. The main beam is broadside, ≤ ±20° (target ~1.5° or narrower).
4. Above 60° the measured level is at least 20 dB below the main beam
   (target 25 dB), subject to the transducer directivity.
5. A frame update to both boards is atomic within one 40 kHz period (or, for
   static beams, the residual transient is documented and accepted).
6. Settings (offset, phase trim, amplitude trim) are repeatable and recorded.

---

## 2. Workspace and version control

Create:

```
E:\LUIS\IPP\fpga\
├── PLAN.md                          (this file)
├── primary\                         (existing repo)
├── secondary\                       (primary-derived baseline; role changes pending)
└── reference\
    └── secondary-original\          (old SonicSurface secondary, git baseline)
```

Status at plan creation:

- `fpga/secondary` baseline created from `fpga/primary` (`ec42fc7`), excluding
  `.git`, build products and the primary JIC.
- `fpga/reference/secondary-original` holds the old 10.24 MHz design for
  reference (MISC_A sync net, pin map, secondary table).

- `fpga/secondary` is its own git repo with the primary `.gitignore`
  (`db/`, `incremental_db/`, `output_files/`, `sim/work/`,
  `simulation/questa/`).
- Atomic commits in each repo: one logical change per commit. Do not mix
  primary, secondary and host changes.
- Tag the current primary state as the single-board baseline before starting
  dual-board work (`git tag single-board-duty-v1`).

---

## 3. Mechanical fixture and wiring

### 3.1 Geometry

Coordinate system: board A occupies `x = 0..150 mm`, `y = 0..150 mm`
(element centers, 16 × 10 mm pitch). Board B is placed at:

```
x_B(k) = 150 mm + gap_x + 5 mm + 10 mm*k      k = 0..15
y_B(k) = 5 mm + 10 mm*k                       k = 0..15
```

`gap_x` is the clear center-to-center extra gap between the nearest elements.
The 5 mm x/y offset is relative to the nominal 10 mm lattice.

- Target offset: **5.00 mm ± 0.15 mm** in x and y.
- Coplanarity / seam step: **±0.25 mm**.
- Gap: minimize. 1 cm is much better than 5 cm (simulated first sidelobe
  −12.5 dB vs −7.6 dB). If the fixture is fixed at 5 cm, plan a 2D taper across
  the 35 cm × 15 cm envelope to suppress the gap fringes.
- Use a machined/laser-cut plate or adjustable brackets with dowel pins into
  the PCB tooling holes. Add shims for the x/y offset; lock with thread-locker.

### 3.2 Sync/control cable

| Primary pin | Secondary pin | Purpose |
|---|---|---|
| `MISC_D` (PIN_120) | `MISC_A` (PIN_65) | 40 kHz carrier-start pulse (one clock at COUNT=0) |
| `MISC_C` (PIN_67, to be added) | `MISC_F` (PIN_115) | Frame-staging/swap strobe (new) |
| GND | GND | Common ground |

Keep the sync cable short and equal-length; verify with a scope that the 40 kHz
phase jitter is < 100 ns. The primary `MISC_C` is currently only a qsf
assignment (the fitter reports it does not exist in the design), so adding it
as an output is a BDF change.

**`MISC_B` is not available as a strobe input.**  In both BDFs the `MISC_B`
pin (PIN_60) goes through `RSSFilter_1` into `UARTReader.i_RX_Serial`; it is
the host UART receive line.  Using it for the strobe would break the
secondary's serial link.  Use `MISC_F` (PIN_115, assigned but absent from the
design) as the new strobe input, or another free pin.

---

## 4. Secondary firmware (`fpga/secondary`)

### 4.1 Create the secondary project from the primary

1. ✅ Old-secondary repo moved to `fpga/reference/secondary-original`.
2. ✅ `fpga/primary` copied → `fpga/secondary` (`.git`, build products and the
   primary `.jic` excluded).
3. ✅ Git initialized; baseline committed as `ec42fc7`.
4. ⏳ Verify a clean compile/fit of the baseline before changing role logic.

### 4.2 Apply the secondary role differences

The primary's 5.12 MHz / 16-phase / 38.4 kBaud / duty-weighting / music-player
design is the common base. Change only the board role:

| Item | Primary | Secondary |
|---|---|---|
| Carrier sync | `MISC_D` (PIN_120) output, one-clock pulse at COUNT=0 | `MISC_A` (PIN_65) input → `SyncTrim` → Counter `sync_reset` |
| Board select | `0xC0` enables, `0xC1` disables | `0xC1` enables, `0xC0` disables |
| `PHASE_CORRECTION` | primary table | secondary table |
| Frame strobe | `MISC_C` output | `MISC_F` input (**not** `MISC_B`) |
| JIC | `QuadrupleBuffer_primary.jic` | `QuadrupleBuffer_secondary.jic` |

Concretely:

- **BDF:** add `MISC_A` input and route it to the Counter `sync_reset` (copy the
  net from `fpga/reference/secondary-original/src/QuadrupleBuffer.bdf`). Remove
  or leave the `MISC_D` output unconnected on the secondary; it must not drive
  the sync cable. Keep the `MISC_B` input for the UART; the strobe needs `MISC_F`.
- **`src/Distribute.vhd`:** reverse the board-select polarity and activate the
  secondary `PHASE_CORRECTION` table. Keep the primary's 4-bit phase nibble,
  `0x10` OFF, amplitude nibble pass-through and 16-phase behavior.
- **`src/PhaseLine.vhd` / `AllChannels.vhd`:** no change from primary; the duty
  weighting and 16-phase logic are already there.
- **`src/music_player.vhd`:** already present from the primary; keep the same
  modes so both boards gate the audio together.
- **UART/baud:** keep 5.12 MHz / 38.4 kBaud / `g_CLKS_PER_BIT=133`.

### 4.3 Do not use the old secondary clocking

The old secondary's 10.24 MHz, 32-phase, 230.4 kBaud, no-music-player design is
not used. Its only useful parts are the MISC_A sync net, the pin map, and the
secondary correction table.

### 4.4 Fine inter-board phase trim

**Implemented in `fpga/secondary`.**  The 16 phase bins (22.5°) are too coarse
for a sub-degree null, so the sync path now has a 50 MHz trim:

- The primary's `MISC_D` is a **one-clock pulse at COUNT = 0** (counts 0 and
  128), not the old `COUNT[6]` square wave.  That makes the sync edge a known
  counter value.
- `SyncTrim` (instantiated inside `Distribute`) uses a 2-flop synchronizer in
  the 50 MHz domain, a 0..255 delay counter (20 ns = 0.288°), and a toggle
  that crosses into the 5.12 MHz domain through a second synchronizer.  The
  old majority filter is removed from the sync path; `MISC_B` (UART RX) is
  untouched.
- `Counter` loads 17 at the default trim (127).  Trim 0..255 spans about
  ±36° around that point; the host sweeps it for the deepest 59° null.
- Command: `0xE0 0x5A <value>`, accepted **only between frames** so a payload
  byte `0xE0` is never mistaken for it.  The value is serialised to
  `SyncTrim` (no 8-bit bus in the schematic) and persists until changed.
- `tb_sync` checks the default alignment, the ±13-clock ends and the ~26-clock
  range; fit is 5,679 / 6,272 LE (91 %).

### 4.5 Frame-staging/swap strobe

Preferred: primary generates a one-cycle pulse on `MISC_C` when its frame
trailer (`0xFD`) is received; the secondary receives it on `MISC_F` and swaps
its shadow buffers on the same 40 kHz edge.

- Add `MISC_C` output to the primary BDF (pin currently assigned but absent
  from the design), driven by a registered pulse from the `0xFD`/swap event.
- Add the strobe input on `MISC_F` (PIN_115), **not** `MISC_B`: `MISC_B` is
  the UART RX line on both boards and cannot be reused.  Feed the strobe into
  the swap control.  Decide whether the secondary's own `0xFD` is ignored
  (strobe only) or whether edge detection prevents a double swap.
- Fallback for the first bring-up: host writes both ports in parallel and
  accepts the ~few-ms skew; add the strobe after the basic two-board beam is
  working.

### 4.6 Required outputs

- `fpga/secondary/QuadrupleBuffer_secondary.jic` generated with
  `quartus_cpf -c -d EPCS16 -s EP4CE6`.
- Flash procedure (same as primary): load the factory SFL
  `D:/altera/quartus/common/devinfo/programmer/sfl_enhanced_01_020f10dd.sof`
  first, then program the secondary JIC.
- Update `fpga/secondary/README.md` with the pin map, sync cable, trim command,
  build and flash steps.

### 4.7 Tests

- Port/adapt the primary testbenches: `tb_phaseline`, `tb_allchannels`,
  `tb_dist_primary`→secondary polarity, `tb_chain` with a secondary frame.
- Add `tb_sync`: MISC_A edge resets the carrier; trim delay shifts the phase;
  board-select polarity (`0xC1` enables, `0xC0` disables); duty codes still work.
- Fit: confirm the secondary fits EP4CE6 with the trim logic (the primary is at
  90 %; the secondary should be similar).

---

## 5. Primary firmware (`fpga/primary`)

1. Add `MISC_C` (PIN_67) as the frame-staging strobe output (BDF pin + logic in
   `Distribute`/top level). Keep it one clock wide and aligned to the 40 kHz
   domain.
2. Optional: add a host-visible status/debug output for swap (not required).
3. Add a testbench for the strobe (assert on `0xFD`, one pulse, no retrigger on
   held bytes).
4. Re-run the full sim suite, fit, regenerate `QuadrupleBuffer_primary.jic`,
   and flash the primary.
5. Commit the strobe change separately from the secondary port.

---

## 6. Host software (`demo/`)

### 6.1 New module `dual_board.py` (or `multi_board.py`)

- `BoardGeometry`:
  - Board A positions and board B positions from `gap_x`, `offset_x=5 mm`,
    `offset_y=5 mm`, orientation 0°.
  - 512 element positions; local logical index and wire order per board.
  - Board-select byte per board: primary `0xC0` enable / `0xC1` disable;
    secondary `0xC1` enable / `0xC0` disable.
- `BoardLink`:
  - Two serial ports (`--board-a-port`, `--board-b-port`), 38400 8N1.
  - Build a 258-byte frame per board with
    `protocol.build_amplitude_frame(local_phases, local_codes)`.
  - Send board-select + frame to each board; parallel writes via threads (or
    pyserial writes on two ports) to minimize skew.
  - `send_trim(delay)` for the secondary fine-delay command (`0xE0 + byte`).
- Dry-run prints both frames' sizes, board select, and the combined geometry.

### 6.2 Combined beam analysis

- New `CombinedBeamAnalyzer` (or extend `BeamAnalyzer` with an `emitters_pos`
  argument and N=512):
  - Actual positions: 512 elements including the 5 mm x/y offset and gap.
  - Metrics: main-lobe peak/gain, −3 dB width in x/y, peak sidelobe over the
    **entire visible hemisphere outside the main lobe** (do **not** exclude the
    59° regions), 59° levels at az 0/90/180/270, active element count.
  - `amplitude_codes`: per-board duty codes; phase bins 0..15.
  - Optimizer: coordinate descent over phase bins and amplitude codes; null
    constraints at 59° (and optional user nulls); objective = peak sidelobe
    outside the main lobe, with a small penalty on main-beam loss.
  - Near-field mode: compute phases for a focus point at the listening distance
    using spherical-wave distances (`acoustics.focus_phases`); the far-field
    analyzer remains for measurement comparisons.
- Taper across the full 35 cm × 15 cm envelope (Hann/Gaussian/Blackman-Harris
  or Tukey) mapped to duty codes; use a lower duty near the gap edges to
  suppress the 5 cm gap fringes.

### 6.3 New CLI `dual_directional_speaker.py`

Flags (draft):

```
--board-a-port COM6 --board-b-port COM7
--alpha 0 --beta 0                      # steering / broadside
--focus-z 1.5                           # near-field focus distance (m), optional
--gap 0.01 --offset-x 0.005 --offset-y 0.005
--amplitude-window hann|gaussian|blackman|tukey|none
--optimize-sweeps N --null 59:0 59:90 59:180 59:270
--calibration dual_calibration.json
--trim-adjust                           # sweep secondary fine delay for best 59 deg null
--compare --dry-run --list-ports
```

Report:

- Predicted 0°, ±10°, ±20°, 40°, 50°, 59° (four azimuths), 70°, 90°.
- Main-beam −3 dB width; 59° null depth; active elements.
- The actual trim value and per-board amplitude scale used.

### 6.4 Calibration file

`dual_calibration.json`:

```json
{
  "board_a_phase_offsets_bins": [ ... 256 ints ... ],
  "board_b_phase_offsets_bins": [ ... 256 ints ... ],
  "board_b_amplitude_scale": 1.0,
  "secondary_fine_delay_steps": 0,
  "measured_gap_mm": 50.0,
  "measured_offset_x_mm": 5.0,
  "measured_offset_y_mm": 5.0
}
```

- Apply per-board phase offsets after the beam pattern is computed, before the
  frame is built (as the single-board `--calibration` does).
- Apply the board-B amplitude scale to the duty codes.
- The measured gap/offset feed the geometry model so the predicted null matches
  the physical mount.

### 6.5 Tests

- `tests/test_dual_board.py`:
  - geometry: 512 positions, offset/gap, board assignment;
  - frame routing: board A/B local wire order and select bytes;
  - offset cancellation: far-field 59° ≤ −20 dB with 5 mm offset; ~0 dB with no
    offset;
  - trim command encoding;
  - near-field focus vs far-field steering;
  - CLI dry-run.
- Keep the single-board tests green; do not modify `protocol.build_frame`
  semantics.

---

## 7. Bring-up and calibration sequence

### 7.1 Firmware bring-up

1. Flash the primary (strobe build) and secondary (duty + trim + sync) with the
   SFL-then-JIC procedure.
2. Probe `MISC_D` (primary) and `MISC_A` (secondary) with a scope: same 40 kHz,
   phase jitter <100 ns.
3. Send a broadside uniform frame to both boards; verify both emit and the
   combined beam is at 0°.

### 7.2 Mechanical and electrical trim

1. Measure the actual gap and x/y offsets (caliper / fixture); record in the
   calibration JSON.
2. With both boards broadside and uniform amplitude, measure the 59° level at
   az 0/90/180/270.
3. Sweep the secondary fine delay (0..255) and the board-B amplitude scale;
   find the deepest 59° null. Record the settings.
4. If the null is shallow, check: sync phase, board select, coplanarity, offset
   (target ±0.15 mm), per-board amplitude match.

### 7.3 Acoustic measurement

- Mic: 1/4" or 1/8", flat to ≥80 kHz; anechoic or time-gated.
- Distance: listen at the demo distance (e.g., 1–2 m) **and** at 2–3 m for a
  near-field/far-field comparison. Note the combined 35 cm aperture Rayleigh
  distance is ~28 m, so far-field measurements require a large space; use
  near-field focusing for the demo.
- Angular cuts: φ = 0°, 90°, 45°; θ = 0, 10, 20, 40, 50, 59, 65, 70, 90°.
- Measure with:
  - uniform amplitude, no offset (reference, 59° lobe present);
  - 5 mm offset, uniform amplitude (59° null);
  - 5 mm offset + taper/optimized (final).
- Thermal: run 30–60 min, log board temperatures and null depth.
- Failure modes to check:
  - no 59° null → sync/firmware/wiring/board select;
  - shallow null → offset tolerance, phase/amplitude mismatch, coplanarity;
  - null present far field but absent near field → near-field focusing needed;
  - gap fringes → smaller gap or stronger taper;
  - drift → thermal symmetry / airflow.

---

## 8. Milestones

| Milestone | Deliverable | Exit criteria |
|---|---|---|
| M0 | Mechanical fixture, 5 mm x/y offset, gap minimized | Offset 5.00 ± 0.15 mm, coplanarity ±0.25 mm, both boards mounted |
| M1 | Secondary Quartus 25.1 port + duty weighting + sync | Clean fit, sim suite passes, JIC generated |
| M2 | Primary strobe + secondary trim command | Scope-verified sync/strobe, trim shifts phase |
| M3 | Host dual-board sender + combined geometry | Dry-run frames correct for both boards |
| M4 | Flash both, broadside beam, 59° null | 59° ≥20 dB below main; null trim recorded |
| M5 | Taper/optimizer, near-field focus | Main beam ≤20°, side floor improved, repeatable |
| M6 | Documentation/demo | README, calibration JSON, measurement log |

---

## 9. Risks and fallbacks

| Risk | Mitigation / fallback |
|---|---|
| 5 mm offset tolerance not achievable | Precision fixture; software phase/amplitude trim; fallback to ≤34.3 kHz carrier prototype |
| 59° null not deep | Measure sync phase, amplitude match, coplanarity; use the null-trim sweep; verify secondary firmware/select polarity |
| 5 cm gap fringes | Minimize gap; 2D Blackman-Harris/Tukey taper across the envelope; optimize phases/amplitudes |
| Near-field null absent at demo distance | Use spherical-wave focusing; measure at the listening plane; accept near-field trade |
| Thermal/air drift | Thermal symmetry, draft shield; log drift; re-trim if needed |
| Fine-delay logic does not fit | The primary fit is 90 %; check the secondary fit early; trim resolution can be traded for range |
| Frame update transient | Parallel UART first; add MISC_C→MISC_F strobe for atomic swap |
| Host/board UART skew | Dual-port parallel writes; optional baud acceleration to 460.8/921.6 kBaud (requires UART divisor changes and host support) |

---

## 10. Open decisions

1. Gap: minimize to ~1 cm, or keep 5 cm and rely on a stronger taper?
2. Frame sync: implement the MISC_C→MISC_F strobe now, or start with parallel
   host writes and add the strobe later?
3. Fine trim: 50 MHz delay counter (0.288°/step) vs. a coarser 5.12 MHz delay
   (2.8°/step). The 50 MHz version is needed for a −30 dB null.
4. UART baud: keep 38.4 kBaud for static beams, or accelerate for dynamic
   steering?
5. Near-field focus: fixed listening point vs. user-supplied `--focus-z`; the
   demo distance determines the phase model.
6. Board-B role: separate secondary firmware vs. a unified build with a strap
   pin. Start with separate builds; unify later if useful.


---

## 11. Simulation finding (2026-11-13): the grating null is a point null

`demo/dual_board.py` now models the measured 512 positions (10.5 mm pitch,
36.75 mm seam, 5.25 mm y offset).  With ideal isotropic elements and uniform
phases the broadside pattern is:

| Offset | Level at 54.75° (az 0/90/180/270) | Peak sidelobe elsewhere |
|---|---|---|
| 0 mm | 0.0 dB | 0.0 dB (the grating lobe) |
| 5.25 mm x/y | below −200 dB | **≈ −2 dB at 53° and 57°** |

The half-pitch shift makes the two boards' contributions cancel **exactly**
at the grating direction, but each board is a 157.5 mm aperture, so the
relative phase changes rapidly away from it.  The grating lobe therefore
splits into two peaks a few degrees either side of the null; it is not
removed.  The same happens for any gap because the cancellation is about the
5.25 mm offset, not the gap.  With the measured geometry the split lobe is
**below 60°**, while the above-60 region is already low.

Consequences:

- Acceptance criterion 2 ("59° ≥20 dB below the main beam") is met only at
  the exact 59.04° direction.  Criterion 4 ("above 60° ≥20 dB below") is
  **not** met by geometry alone in the isotropic model: the 61° peak is near
  0 dB.
- The 10 mm piston's directivity attenuates 60° by roughly 15 dB, so the
  practical peak may be around −15 dB.  This must be measured; it is the
  real side-leak limit of this two-board arrangement.
- `peak_sidelobe_db` in `CombinedBeamAnalyzer` (whole visible hemisphere) is
  the honest metric; `grating_lobe_db` alone is misleading.  The analyzer now
  also reports `far_sidelobe_db`, the peak above `--side-start` (default 60°),
  and models the 10 mm circular piston directivity by default.
- With the measured geometry and directivity, broadside uniform phases give a
  far peak (above 60°) of **−30.2 dB** and an overall peak of −14.3 dB; three
  far-region optimizer sweeps reach **−36.7 dB** for about −2.2 dB main gain.
  The remaining split lobe is near 53°, below the 60° boundary.  The optimizer
  uses a near-sidelobe guard (`--near-weight 0.5`) because targeting >60°
  alone dumps energy just outside the main lobe.
- Removing the grating lobe itself still requires a carrier ≤34.3 kHz, a
  ≤4.3 mm lattice, or an aperiodic layout.  A host taper or optimizer can
  trade main-beam gain against the split lobes but cannot make the lattice
  alias disappear.

## 12. Status at 2026-11-13

- **M1/M2 complete.** `fpga/secondary` has the `MISC_A` pulse sync through
  `SyncTrim` (Counter loads 17 at trim 127), the 50 MHz fine-trim command
  `0xE0 0x5A <value>`, reversed board select (`0xC1` enables), the secondary
  correction table (permuted to wire order), the removed MISC_D output, a
  91 % fit, and `QuadrupleBuffer_secondary.jic`.  `sim/run_sim.ps1`: all 12
  tests pass, including `tb_sync` and `tb_dist_secondary`.
- **Primary** outputs the one-clock `COUNT=0` pulse on `MISC_D`; its suite
  passes including `tb_carrier_sync`; the primary JIC is regenerated.
- **Host dual-board support complete (M3/M4 software part).**
  `demo/dual_board.py` and `demo/dual_directional_speaker.py` build both
  frames, send them in parallel, model the combined pattern and report the
  split lobes.  182 Python tests pass.
- **Not yet done:** flash the secondary, connect `MISC_D`→`MISC_A` and GND,
  measure the 59°/57°/61° levels, decide the gap from the fixture, and add
  the `MISC_C`→`MISC_F` frame strobe if the measurements need it.
- The `MISC_C` → `MISC_B` strobe in the original plan is not possible:
  `MISC_B` is the UART RX line.  A future strobe needs `MISC_F` or another
  free pin.
