---
name: power-simulink-rule
description: >
  Battle-tested rules for building power-electronics simulations in Simulink with
  the black-block Specialized Power Systems (SPS) library: fixed modeling workflow,
  carrier-comparison PWM, PI double loops, SVPWM, resolver/solver and sampling-time
  settings, naming conventions, and safety floors. Use when building, modifying, or
  reviewing SPS-based models such as PFC rectifiers, DC-AC inverters, Buck-Boost
  converters, or when reproducing PWM/PI/SVPWM control logic.
---

# power-simulink-rule

A Simulink power-electronics modeling playbook built entirely from **reverse-engineering 10 real, working `.slx` models**. Goal: a model built with these rules follows one coherent, proven style — **Simscape Electrical Specialized Power Systems (the "black block" library) for the power stage + discrete `powergui` solver + hand-built carrier-comparison PWM + PI double loops + Chinese inline comments**. Every rule traces back to an actual parameter measured in a real model (see `references/models-analysis.md`); when in doubt, the measured value wins.

## When to use & how

**Applies when any of these is true:**
- Building a new power-electronics simulation (PFC, inverter, Buck-Boost, AC-AC, etc.)
- Modifying or reviewing an existing model that should follow this style
- Reproducing the control logic (PWM modulation, PI double loops, SVPWM)
- Configuring solvers, sampling times, or `powergui` parameters

**Workflow:**
1. Read this file for the core rules; go to `references/rules.md` (detailed spec), `references/library-guide.md` (block library selection), `references/models-analysis.md` (per-model evidence) for details
2. Build in the order: circuit modeling steps → control templates → library selection → naming → parameter config
3. Use `scripts/extract_model_params.m` to extract parameters from an existing model as a reference
4. After building, self-check rule by rule (solver, sampling time, PWM frequency, naming, safety floors especially)

**Environment prerequisites (when driving MATLAB directly):**
- MATLAB R2024b must first run `matlab.engine.shareEngine`
- Connect through a MATLAB MCP / Simulink MCP tool (`access_matlab`, then `run_matlab_code` / `read_simulink_system`)
- `cd` or addpath to the model directory (some MCP servers block absolute paths)
- Model names starting with a digit / parentheses / hyphens (e.g. `222ACACbuckboost`, `AC-DC(PFC)`) cannot be `load_system`-ed directly — `copyfile` to a temp dir with a legal name first
- Read-only models are analyzed read-only, never saved

## Circuit modeling steps (in order)

See `references/rules.md` §1. Core sequence:

1. **Place `powergui` first**: from the SPS library, set Discrete mode
2. **Build the power stage** (SPS library):
   - AC source: `AC Voltage Source` (e.g. `Amplitude=24*sqrt(2), Frequency=50`) or three single-phase sources `UA/UB/UC` (phases 0/-120/-240)
   - DC source: `DC Voltage Source`
   - Switches: `Mosfet` (Ron=0.1 default) or `IGBT//Diode` (Ron=1e-3 default); complementary legs get a `NOT` signal
   - Passives: `Series RLC Branch` (BranchType L/R/C/RL/RC; filter inductors 1mH~13mH, bus caps 30uF~4.3mF, loads 5~50Ω)
   - Current sensing: a `Series RLC Branch` set to `BranchType=R, Resistance=1e-5` (milliohm shunt) in series, read via `Multimeter`/`Current Measurement`
3. **Measurements & display**: `Current Measurement`/`Voltage Measurement`/`Three-Phase V-I Measurement` (LabelV=Vabc, LabelI=Iabc), `Multimeter`, `Scope` (multi-channel), `Display`
4. **Control loops** (templates below): sample → transform → PI → modulate → PWM
5. **PWM & gating**: carrier comparison + `NOT` for complementarity + `From/Goto` distribution to gates
6. **Logging**: `ToWorkspace` (`log_` prefix) for key signals
7. **Solver** (see parameter section)

## Control logic templates (copy these)

### PWM generation (two ways)
**Way A: library block (Buck-Boost / general)**
- `PWM Generator (DC-DC)`: `Fsw=20000` (20kHz), `Ts=0` (inherit)
**Way B: hand-built carrier comparison (PFC/inverters — preferred)**
- `Repeating Sequence` triangle carrier: period = 1/Fsw (e.g. `rep_seq_t=[0 1/20000/2 1/20000], rep_seq_y=[0 7200 0]`; amplitude 7200 mirrors an MCU ARR register)
- Or sawtooth: `rep_seq_t=[0 10e-6], rep_seq_y=[0 1]` (100kHz normalized)
- `RelationalOperator` (`>`) compares duty vs carrier
- Complementary leg: `NOT` + optional `Bias` (One minus duty)

### PI controller (standard config)
- `PID Controller` block: `Controller=PI, Form=Parallel, TimeDomain=Continuous-time, IntegratorMethod=Forward Euler, FilterMethod=Forward Euler, N=100`, D=0
- Sampling time: inner loop explicit (e.g. 2e-5), outer loop -1 (inherit)
- Field-measured parameter ranges: three-phase current inner loop P=30/I=20, outer loop P=30/I=8; single-phase PFC P=6.65/I=12 and P=12/I=5; three-phase PFC P=25/I=0.01, voltage loop P=5/I=29.26
- Alternative hand-written style (scan platform): `Gain`(Kp) + `DiscreteIntegrator`(gainval=Ki) + `Saturate` + feedforward `Sum`(++)
- Saturation: `Saturate` (voltage loop [-190,190], duty [0.02,0.98])

### Quasi-PR controller (current inner loop, single-phase PFC)
- Transfer function: `G(s) = Kp + 2*Kr*wc*s/(s^2 + 2*wc*s + w0^2)`, w0=`2*pi*50`, wc=`2*pi*5`; Tustin-discretized into a `MATLAB Function` with `persistent` states
- Three hard-won field rules (full details in `references/rules.md` §2.7):
  1. Put a `ZeroOrderHold` (2e-5) before the input to force discrete sampling, or persistent initialization errors out
  2. Anti-windup is mandatory: resonator state clipped at ±0.25, output at ±0.3 — otherwise large errors blow the output up into bang-bang oscillation
  3. Feedforward does the heavy lifting, PR only trims: `uin/(2*Uo)` + inductor voltage `L*w*Iref_peak*cos(wt)/(2*Uo)` (PR has 0° phase at resonance and cannot fix the inductor's 90° lag)
- Field-stable operating point: Kp=1, Kr=50, output clip ±0.3; Kp≥2 or clip≥0.5 lets PR dominate the modulation and Uo collapses to ~300

### Reference-frame transforms (three-phase, subsystem templates)
- **Clarke (abc→αβ)**: `Fcn` blocks inside a `Subsystem`: `(u(1)-u(2)/2-u(3)/2)*2/3`, `(sqrt(3)*u(2)/2-sqrt(3)*u(3)/2)*2/3` (mind the 2/3 factor)
- **Park (abc→dq)**: `u(1)*cos(u(3))+u(2)*sin(u(3))`, `-u(1)*sin(u(3))+u(2)*cos(u(3))`
- **Inverse Park (dq→αβ)**: `u(1)*cos(u(3))-u(2)*sin(u(3))`, `u(1)*sin(u(3))+u(2)*cos(u(3))`
- **Inverse Clarke**: `u(1)-u(2)/2-u(3)/2`, `sqrt(3)*u(2)/2-sqrt(3)*u(3)/2`
- Angle source: `Repeating Sequence` 50Hz ramp (`rep_seq_t=[0 1/50], rep_seq_y=[0 2*pi]`)

### SVPWM (7-segment, template in models-analysis.md)
- `MATLAB Function` (Stateflow EML): inputs Valpha/Vbeta/Udc/Tpwm/ARR → sector detection → X/Y/Z → T1/T2 → ta/tb/tc → outputs `Tcm1/2/3` (normalize ×2/Tpwm, then ×ARR)
- Full code in `references/models-analysis.md`

### Decoupling feedforward (house style)
- Inductor impedance: `Gain` values like `2e-3*2*pi*50`, `2*pi*50*1e-3` (named Wl / L di dt feedforward)
- Capacitor admittance: `2*pi*50*220e-6` (named WC)
- Single-phase PFC phase feedforward: `WL = 1e-3*100*pi`

### Test signals (scan-platform style)
- `MATLAB Function` (Stateflow EML) generates a swept reference: 100kHz control period, 10 periods held per point (10kHz reference update), base=0.1/rise=0.6 triangle sweep + step jump
- `ZeroOrderHold` at 100kHz (10e-6) labeled "ADC sample 100k"

## Library selection guide

**Only two libraries ever appear** (details in `references/library-guide.md`):
1. **Simscape Electrical Specialized Power Systems (SPS, the black-block library)** — power stage only:
   `powergui`, `AC Voltage Source`, `DC Voltage Source`, `Mosfet`, `IGBT//Diode`, `Series RLC Branch`, `PWM Generator (DC-DC)`, `RMS`, `Multimeter`, `Current/Voltage Measurement`, `Three-Phase V-I Measurement`
2. **Core Simulink library** — control & signal processing:
   `Constant`, `Gain`, `Sum`, `Bias`, `Saturate`, `Switch`, `RelationalOperator`, `Logic`, `ZeroOrderHold`, `DiscreteIntegrator`, `PID Controller`, `Repeating Sequence`, `Fcn`, `MATLAB Function` (Stateflow), `ToWorkspace`, `Scope`, `Display`, `From/Goto`, `Mux/Demux`, `Clock`

**Never use**: Simscape Foundation (physical-network) blocks, SimElectronics, or any third-party electrical library — none of the source models ever contained one.

## Naming conventions

- **Signal/block names = physical meaning + frequency/unit**: `Carrier 100k`, `Frequency Hz`, `Iout ADC sample 100k`, `Slope sample 100k`
- **Control nodes**: `Duty center`, `Duty limit`, `Invert duty`, `One minus duty`, `Voltage to duty`, `PWM left/right`, `NOT left/right`
- **Controllers**: `PI fast Kp`, `PI fast Ki`, `PI fast voltage sum`, `PI fast voltage limit` (fast/slow loops tagged "fast")
- **Feedforward**: `L di dt feedforward`, `WL`, `WC`, `Wl`
- **Devices**: `Mosfet1..8`, `IGBT//Diode1..11`, `VD1..9` (diodes), `VT1..9` (thyristors)
- **Logging**: `ToWorkspace` variable names use a `log_` prefix + purpose: `log_Io`, `log_Ir`, `log_PI_duty`, `log_PI_voltage`
- **Three-phase**: `UA/UB/UC` (sources), `Switcha1/2`, `Switchb1/2`, `Switchc1/2`
- **Transform subsystems**: `Subsystem1/2/3/5/9` reused (names free, contents standard)
- **Comments**: colloquial Chinese explaining *why* (e.g. `% 扫描频率切换`, `% 正半周`); parameters written as formulas (`24*sqrt(2)`, `1/(2*200)`)

## Parameter configuration (solver / sampling)

- **powergui**: `SimulationMode=Discrete` (single exception: one teaching model uses Continuous); `SampleTime` 1e-7 ~ 50e-7 (100ns~500ns); frequency parameter 50/60
- **Solver**: `VariableStepAuto`, `StopTime` 0.05~2 (0.5 most common), `MaxStep=auto` (occasionally 1e-7)
- **Control sampling**: inner loop 2e-5 (50kHz, single-phase PFC) / 50e-9 (three-phase PFC) / -1 inherit (inverter); ZOH 10e-6 (100kHz)
- **PWM frequency**: 20kHz (Buck-Boost / three-phase inverter / three-phase PFC), 50kHz (single-phase PFC), 100kHz sawtooth (scan platform)
- **Parameters as expressions**: always write formulas, never pre-computed numbers (`24*sqrt(2)`, `1/20000`, `2e-3*2*pi*50`, `1/(2*200)`)
- **Switch defaults**: Mosfet `Ron=0.1, Rd=0.01, Vfd=0, Rs=1e5, Cs=inf, Measurements=on`; `IGBT//Diode` `Ron=1e-3`; do not tweak library defaults

## Safety floors (non-negotiable)

- **Read-only models stay read-only**; analyzing a model means `copyfile` to a temp dir and rename — never touch the original file
- Complementary PWM (NOT inversion) must be preserved — no shoot-through between high/low sides
- Current sensing via milliohm shunts (1e-5~1e-7) + isolated measurement; never short-circuit sensing
- Control outputs must be saturated; typical duty clip [0.02, 0.98]
- Back up any model before modifying it
- With non-ASCII paths, verify encoding with `disp(pwd)` in the MATLAB session first

## What NOT to do

- Do not use components that never appear in the source models (GTOs, non-ideal-transformer types, Simscape Foundation blocks)
- Do not invent parameters: every rule here is grounded in a measured value in `references/models-analysis.md`; new-model parameters need either user confirmation or a circuit calculation
- Do not switch `powergui` to Continuous (except teaching demos)
- Do not modify `.slxc` caches, `.autosave` files, or read-only models
- Do not write "standards" beyond what the models actually do — this playbook only claims what was measured

## Evidence base

All rules derive from per-model analysis in `references/models-analysis.md`. Models are anonymized with codes (BB-A, PFC-1P-A, INV-3P, SCAN, EDU, PFC-PR, ...); the code map is documented at the top of that file.
