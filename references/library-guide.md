# Block library selection guide (library-guide.md)

## General principle

All 10 source models use **only two libraries**; new models must do the same:

1. **Simscape Electrical Specialized Power Systems** (SPS / PSB — the "black block" library) — power stage
2. **Core Simulink library** (Commonly Used Blocks and sublibraries) — control & signal processing

## I. SPS library — power stage

| Block | Usage / parameters | Source model |
|---|---|---|
| `powergui` | SimulationMode=Discrete (EDU: Continuous), SampleTime=1e-7~50e-7 | all |
| `AC Voltage Source` | Amplitude=24*sqrt(2) or 220*sqrt(2); Frequency=50; SampleTime=0; Measurements=Voltage; BusType=swing | BB, PFC |
| `DC Voltage Source` | Amplitude=100/200 | INV-3P, SCAN |
| `Mosfet` | all defaults: Ron=0.1, Lon=0, Rd=0.01, Vfd=0, IC=0, Rs=1e5, Cs=inf, Measurements=on | BB, INV-3P, SCAN |
| `IGBT//Diode` | Ron=1e-3, Rs=1e5, Cs=inf, Measurements=on | PFC family |
| `Diode` | Ron=0.001, Vf=0.8, Rs=500, Cs=250e-9 | EDU |
| `Thyristor` (VT) | Ron=0.01, Rd=.01, Rs=5, Cs=1e-6 | EDU |
| `Series RLC Branch` | BranchType=L/R/C/RL/RC as needed; values as numbers or expressions; shunts use BranchType=R + R=1e-5~1e-7 | all |
| `PWM Generator (DC-DC)` | Fsw=20000 (20kHz), Ts=0 | BB family, SCAN |
| `RMS` | TrueRMS=on, Freq=50, RMSInit=120, Ts=0 | BB-B, SCAN |
| `Multimeter` | paired with blocks that have Measurements=on | BB, SCAN |
| `Current Measurement` | PhasorSimulation=off | PFC, INV-3P |
| `Voltage Measurement` | PhasorSimulation=off | all |
| `Three-Phase V-I Measurement` | VoltageMeasurement=phase-to-ground; SetLabelV=on, LabelV=Vabc; CurrentMeasurement=yes, SetLabelI=on, LabelI=Iabc | PFC-3P |
| `Linear Transformer` | UNITS=pu, NominalPower=[250e6 20e3], winding1=[220 0 0] | EDU |
| `Three-Phase Source` | **not used** — three independent AC Voltage Sources (UA/UB/UC) instead | three-phase models |

## II. Core Simulink library — control & signal processing

| Block | Purpose | Key settings |
|---|---|---|
| `Constant` | references/constants | expressions directly: 400, 7200, 1/20000, 220*sqrt(2) |
| `Gain` | proportional/feedforward/scaling | expressions directly: 1/(2*200), 2e-3*2*pi*50, -1, 1/30 |
| `Sum` | error/accumulation | signs explicit: +-, +++, \|+- |
| `Bias` | DC offset | Duty center=0.5, One minus duty=1 (implements 1-duty) |
| `Saturate` | clipping | Duty limit [0.02,0.98], PI fast voltage limit [-190,190] |
| `Switch` | mode/channel select | Threshold=0, Criteria=u2>=Threshold (or u2>Threshold) |
| `RelationalOperator` | carrier comparison | Operator=> (duty vs carrier) |
| `Logic` (NOT) | complementary signal | NOT left/right |
| `ZeroOrderHold` | sampling hold | Ts=10e-6 (100kHz "ADC sample 100k") |
| `DiscreteIntegrator` | manual integrator (PI's I) | gainval (R2024b parameter name)=Ki, IC=0 |
| `PID Controller` | PI controller | Controller=PI, Form=Parallel, TimeDomain=Continuous-time, IntegratorMethod=Forward Euler, N=100, D=0 |
| `Repeating Sequence` | carrier/angle | triangle 20kHz [0 7200 0]; sawtooth 100kHz [0 1]; ramp 50Hz [0 2*pi] |
| `Fcn` | transform formulas | u(1)*cos(u(3))+u(2)*sin(u(3)) etc. |
| `MATLAB Function` (Stateflow EML) | SVPWM/test signals/logic | Chinese comments, %#codegen |
| `PLL` | phase lock | Fmin=50, ParK=[180,3200,1], Ts=1e-6, AGC=on (PFC-1P-B) |
| `ToWorkspace` | logging | variable names log_* |
| `Scope`/`Display` | viewing | multi-channel Scope, Display1..4 |
| `From`/`Goto` | signal routing | heavily used at top level (From1..36/Goto1..26) |
| `Mux`/`Demux` | combine/split | transform subsystem outputs |
| `Clock`/`DigitalClock` | time | SCAN uses Clock to drive the sweep |
| `Mod`, `Trigonometric Function`, `Product` | math | phase generation (mod, sin/cos, multiply) |

## III. Explicitly forbidden libraries

- ❌ Simscape Foundation (physical-network blocks outside SPS — no electrical network solver)
- ❌ SimElectronics / any electrical library other than (new) SPS
- ❌ Simscape Electrical base-domain blocks (non-SPS)
- ❌ Third-party power-electronics libraries
- ✅ 100% of the source models use SPS + core Simulink — this is an iron rule

## IV. How to verify library compliance

Check block library origin via the `SourceBlock` parameter:

```matlab
blks = find_system(mdl, 'LookUnderMasks', 'all', 'FollowLinks', 'on');
for i = 2:numel(blks)
    src = get_param(blks{i}, 'SourceBlock');  % SPS shows spsXxxLib/...
    % expected: sps*Lib/*, simulink/*, built-in (core Simulink)
end
```

Compliant source prefixes: `sps*` (Simscape Electrical SPS), `simulink/`, `built-in`, `slpidlib` (PID), `sflib` (Stateflow).
Anything else → violates the style; replace it.
