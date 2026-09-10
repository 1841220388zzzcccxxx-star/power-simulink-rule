# Detailed rules (rules.md)

This file expands `power-simulink-rule` into full detail. Every rule is tagged with its source model (model list in `models-analysis.md`). **All rules are grounded in parameters measured from real, working models.**

Models are referred to by anonymized codes: `SCAN` (power/frequency sweep platform), `INV-3P` (three-phase inverter), `PFC-3P` (three-phase PFC rectifier), `PFC-1P-A/B` (single-phase PFC family), `BB-A/B` (Buck-Boost family), `EDU` (early teaching model), `PFC-PR` (quasi-PR tuning testbed).

---

## 1. Circuit modeling steps (full version)

All models follow a fixed build order. `SCAN` (newest) and `INV-3P` (most complex) are the reference baselines:

### Step 0: place powergui
- Drag `powergui` from the SPS library
- `SimulationMode=Discrete`, `SampleTime=1e-7~50e-7`
- Source: all models (EDU exception: Continuous)

### Step 1: power stage
- **Sources**:
  - AC: `AC Voltage Source`, `Amplitude=220*sqrt(2) or 24*sqrt(2)`, `Phase=0`, `Frequency=50`, `SampleTime=0`, `Measurements=Voltage`, `BusType=swing`
  - Three-phase: three independent sources named `UA/UB/UC`, phases `0/-120/-240` (EDU uses 30/-90/-210)
  - DC: `DC Voltage Source` (Amplitude=100/200)
- **Switches**:
  - Low-power / high-frequency: `Mosfet` (Ron=0.1, Lon=0, Rd=0.01, Vfd=0, IC=0, Rs=1e5, Cs=inf, Measurements=on) — all defaults
  - High-power / rectification: `IGBT//Diode` (Ron=1e-3, Rs=1e5, Cs=inf, Measurements=on)
  - Thyristors (old model): `VT*` (Ron=0.01, Rd=.01, Rs=5, Cs=1e-6) + `VD*` diodes (Ron=0.001, Vf=0.8, Rs=500, Cs=250e-9)
  - Naming: `Mosfet1..8`, `IGBT//Diode1..11` (auto-numbered)
- **Passives**: `Series RLC Branch` (BranchType L/R/C/RL/RC as needed):
  - Filter inductors: L=1mH~13mH (SCAN boost inductor 13mH)
  - Bus capacitors: C=30uF (BB-A), 220uF (INV-3P), 4.3mF (PFC-3P), 48mF (PFC-1P)
  - Load resistors: R=5Ω (inverter), 16Ω (PFC), 20/50Ω (Buck-Boost)
  - Output filter RC: R=0.0001 + C=2200uF (SCAN)
  - **Shunt**: `BranchType=R, Resistance=1e-5` (BB-A) or `1e-7` (INV-3P), `Measurements=Branch voltage`, in series with the measured leg
- **Signal routing**: `From/Goto` buses (top level uses dozens: From1..36 / Goto1..26 distributing gate signals); electrical connections are direct wires

### Step 2: measurement & display
- `Current Measurement` / `Voltage Measurement` (PhasorSimulation=off)
- `Multimeter` (paired with blocks that have Measurements=on)
- `Three-Phase V-I Measurement` (VoltageMeasurement=phase-to-ground, SetLabelV=on, LabelV=Vabc, CurrentMeasurement=yes, SetLabelI=on, LabelI=Iabc)
- `Scope` (2~4 channels), `Display` (numeric readouts, Display1..4)

### Step 3: control loops
See §2. Overall chain: sampling (ZOH/measurement) → transform (three-phase) → error → PI → saturation → feedforward → duty → PWM.

### Step 4: PWM & gating
See §2. `From/Goto` distributes PWM to gates; complementary legs use `NOT`.

### Step 5: logging
`ToWorkspace`: variable names with `log_` prefix (log_Io, log_Ir, log_PI_duty, log_PI_voltage).

### Step 6: solver
`VariableStepAuto`, `StopTime=0.05~2`. powergui discrete.

---

## 2. Control logic templates (full version)

### 2.1 PWM generation

**Template A (library block PWM Generator (DC-DC))** — Buck-Boost family:
```
PWM Generator (DC-DC): Fsw=20000 (20kHz), Ts=0 (inherit)
```
Output goes to NOT for complementarity, then From/Goto distribution.

**Template B (hand-built carrier comparison)** — PFC/inverter/SCAN, the house preference:
```
Triangle carrier (three-phase PFC/inverter, 20kHz, amplitude = ARR):
  Repeating Sequence: rep_seq_t=[0 1/20000/2 1/20000], rep_seq_y=[0 7200 0]
Triangle carrier (single-phase PFC, 50kHz, normalized):
  Repeating Sequence: rep_seq_t=[0 1e-5 2e-5], rep_seq_y=[0 1 0]
Sawtooth carrier (SCAN, 100kHz, normalized):
  Repeating Sequence: rep_seq_t=[0 10e-6], rep_seq_y=[0 1]
Compare:
  RelationalOperator (Operator=>): duty vs carrier
Complementary:
  NOT (NOT left / NOT right), or Bias as 1-duty (One minus duty)
```

### 2.2 PI controller

**Configuration** (identical across all models):
```
PID Controller block: Controller=PI, Form=Parallel, TimeDomain=Continuous-time,
                      IntegratorMethod=Forward Euler, FilterMethod=Forward Euler,
                      UseExternalTs=off, N=100, D=0
```

**Measured parameters** (source model code in parentheses):
| Model | Loop | P | I | SampleTime |
|---|---|---|---|---|
| INV-3P | current inner ×4 | 30 | 20 | -1 |
| INV-3P | current inner ×2 | 40 | 15 | -1 |
| INV-3P | outer ×2 | 30 | 8 | -1 |
| PFC-1P-A/B | voltage outer | 6.6543 | 12 | 2e-5 |
| PFC-1P-A/B | current inner | 12 | 5 | 2e-5 |
| PFC-3P | current ×2 | 25 | 0.01 | 50e-9 |
| PFC-3P | voltage | 5 | 29.26 | 50e-9 |
| SCAN | current inner | 0.8 | 1 | -1 |

**Hand-written PI (SCAN voltage loop style)**:
```
Sum_Err (Iref - Iout)
  → Gain (PI fast Kp=500) → Sum (PI fast voltage sum, signs=+++)
  → DiscreteIntegrator (gainval=12000, IC=0) → same Sum
  → Gain (L di dt feedforward=13e-3) → same Sum
  → Saturate (PI fast voltage limit: [-190,190])
  → Gain (Voltage to duty = 1/(2*200)) → Bias (Duty center=0.5)
  → Saturate (Duty limit: [0.02,0.98]) → PWM comparison
```

### 2.3 Reference-frame transforms (three-phase, Fcn pairs in a Subsystem)

| Transform | Fcn1 | Fcn2 | Source |
|---|---|---|---|
| Clarke (with 2/3) | `(u(1)-u(2)/2-u(3)/2)*2/3` | `(sqrt(3)*u(2)/2-sqrt(3)*u(3)/2)*2/3` | PFC-3P |
| Park (abc→dq) | `u(1)*cos(u(3))+u(2)*sin(u(3))` | `-u(1)*sin(u(3))+u(2)*cos(u(3))` | PFC-3P |
| Inverse Park (dq→αβ) | `u(1)*cos(u(3))-u(2)*sin(u(3))` | `u(1)*sin(u(3))+u(2)*cos(u(3))` | PFC-3P |
| Inverse Clarke | `u(1)-u(2)/2-u(3)/2` | `sqrt(3)*u(2)/2-sqrt(3)*u(3)/2` | PFC-3P |

Angle source: `Repeating Sequence` (`rep_seq_t=[0 1/50], rep_seq_y=[0 2*pi]`, 50Hz ramp) or a PLL block (PFC-1P-B: Fmin=50, ParK=[180,3200,1], TcD=1e-4, MaxRateChangeFreq=12, FilterCutOffFreq=25, Ts=1e-6, AGC=on).

### 2.4 SVPWM (7-segment, MATLAB Function template)

Inputs: Valpha, Vbeta, Udc, Tpwm, ARR; outputs: Tcm1, Tcm2, Tcm3, sector.
Full code in `models-analysis.md` (identical template in PFC-3P and INV-3P).
Key points: sector from signs of Vref1/2/3 → X/Y/Z dwell times → switch assigns T1/T2 → over-modulation rescale → ta/tb/tc → normalize ×2/Tpwm → ×ARR clip.

### 2.5 Decoupling feedforward

- `Wl/Wl1/Wl4/Wl5 = 2*pi*50*1e-3` (inductor impedance, inverter dq decoupling)
- `WC/WC1 = 2*pi*50*220e-6` (capacitor admittance)
- `WL = 1e-3*100*pi` (single-phase PFC reactance feedforward)
- `Gain/Gain1 = 2e-3*2*pi*50` (PFC-3P)
- `L di dt feedforward = 13e-3` (SCAN, direct L value)

### 2.6 Test signals (SCAN style, MATLAB Function)

- `MATLAB Function` (Stateflow EML): 100kHz control (control_hz=100000), 10 periods held per point (10kHz reference update), `base=0.1, rise=0.6` triangle sweep, step jump (Jump=0.1, Jump time ratio=0.02)
- Reference normalization: `ref_gain=10.0, ref_bias=-0.45` (downstream gain/bias folded into the function)
- `ZeroOrderHold` sampling: `Iout/Iref/Slope ADC sample 100k`, Ts=10e-6

### 2.7 Quasi-PR controller (current inner loop, field-tuned on PFC-PR)

**Transfer function**: `G(s) = Kp + 2*Kr*wc*s/(s^2 + 2*wc*s + w0^2)`, w0=2*pi*50 (resonant line frequency), wc=2*pi*5 (bandwidth)
**Discretization**: bilinear (Tustin) → 2nd-order difference equation, persistent states (MATLAB Function / Stateflow EML)

**Measured field lessons (must-follow):**
1. **The MATLAB Function block must be explicitly discretized**: put a ZeroOrderHold (2e-5 = 50kHz) before its input; otherwise persistent initialization errors out
2. **Internal anti-windup is mandatory**: resonator state clip (±0.25) + output clip (±0.3); without them a large error blows the output up (±3000) → saturation → bang-bang loss of control
3. **Feedforward is required, PR only trims**:
   - uin feedforward: `uin/(2*Uo)` normalized (measured 1/800~1/880; too strong and open-loop rectification self-sustains, killing the voltage loop)
   - Inductor drop feedforward: `L*w*Iref_peak*cos(wt)/(2*Uo)` (Gain expression `2e-3*2*pi*50/(2*400)*1.5`), compensating the 90° inductor lag (without it, Iin lags 46°)
   - PR alone cannot fix the 90° inductor lag (PR phase is 0° at resonance)
4. **Measured PR parameters**: Kp=1, Kr=50, wc=2*pi*5, output clip ±0.3 is the stable operating point; Kp≥2 or clip≥0.5 lets PR dominate the modulation and Uo collapses to ~300
5. **Known limitation**: when the uin feedforward and amplitude are not fully decoupled the voltage loop negative-saturates (Iref→0) and Uo is set by feedforward self-rectification (measured ~388-410V vs 400V reference, ±3%); precise 400V needs the feedforward scaled by amp with amp clipped to [0,1]

---

## 3. Naming conventions (full version)

| Category | Rule | Example |
|---|---|---|
| Signals | physical meaning + frequency/unit | `Carrier 100k`, `Frequency Hz`, `Iout ADC sample 100k` |
| Control nodes | English function phrase | `Duty center`, `Duty limit`, `Invert duty`, `One minus duty`, `Voltage to duty` |
| PWM | left/right position | `PWM left`, `PWM right`, `NOT left`, `NOT right` |
| Controllers | loop name + fast | `PI fast Kp`, `PI fast Ki`, `PI fast voltage limit` |
| Feedforward | physics abbreviation | `WL`, `WC`, `Wl`, `L di dt feedforward` |
| Devices | type + index | `Mosfet1..8`, `IGBT//Diode1..11`, `VD1..9`, `VT1..9` |
| Three-phase | phase + index | `UA/UB/UC`, `Switcha1/2`, `Switchb1/2`, `Switchc1/2` |
| Logging | log_ + signal | `log_Io`, `log_Ir`, `log_PI_duty`, `log_PI_voltage` |
| Constants | semantic | `Constant1=400` (voltage ref), `Constant6=7200` (carrier amplitude), `Constant5=1/20000` |
| Comments | colloquial Chinese | `% 扫描频率切换`, `% 正半周`, `% 确保时间非负` |

---

## 4. Parameter configuration (full version)

- **Solver**: `VariableStepAuto` (SolverType=Variable-step), `StartTime=0.0`, `StopTime=0.05~2` (0.5 most common), `MaxStep=auto` (PFC-3P sets 1e-7)
- **powergui**: `SimulationMode=Discrete`, `SampleTime=1e-7` (PFC/SCAN) or `50e-7` (Buck-Boost/inverter), `frequency=60` (default), `Iterations=50`
- **Sampling times**: control loop 2e-5 (50kHz single-phase PFC) ~ 50e-9 (PFC-3P); ZOH 10e-6 (100kHz); symbolic `Ts` variable (BB-B references it 78×, must be defined in the workspace)
- **Parameter expressions**: always formulas (`24*sqrt(2)`, `1/20000`, `2e-3*2*pi*50`, `1/(2*200)`, `1/(220*sqrt(2))*pi`)
- **Switch defaults**: see §1; library defaults are not customized
- **ToWorkspace**: variable names `log_*`, logging control signals

---

## 5. Safety floors (full version)

1. Read-only models are analyzed read-only, never saved with modifications
2. To analyze, `copyfile` to a `tempname` directory and rename before loading; never touch the original file (model names starting with digits/parentheses/hyphens are rejected by `load_system`)
3. Complementary PWM (NOT / 1-duty) must be preserved — anti-shoot-through
4. Current sensing via milliohm shunts (1e-5/1e-7) + isolated measurement; never sense by shorting
5. Control quantities must be clipped: duty [0.02,0.98], voltage [-190,190] (anti-integrator-windup overflow)
6. With non-ASCII paths, verify encoding with `disp(pwd)` first; fall back to full paths if garbled
7. Model families have many copies (BB-A/A′/BB-B, PFC-3P root and subfolder) — confirm which version you are modifying before editing
