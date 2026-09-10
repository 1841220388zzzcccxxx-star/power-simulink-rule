# Per-model evidence base (models-analysis.md)

This file records the measured analysis of 10 real `.slx` models — the factual basis for every rule in this playbook. Each entry lists: topology, parameters, control logic, and naming examples.

**Anonymization note:** source models are private; they are referred to here by codes only:

| Code | Topology | Notes |
|---|---|---|
| `SCAN` | DC-DC buck-type power/frequency sweep testbed (100kHz fast loop) | newest, style-defining baseline |
| `INV-3P` | three-phase two-level inverter | most complex (~150 blocks) |
| `PFC-3P-A / PFC-3P-B` | three-phase boost PFC rectifier | two identical copies |
| `PFC-1P-A` | single-phase 4-switch PFC (bipolar modulation) | known to diverge when simulated as-is — structure reference only |
| `PFC-1P-B` | simplified single-phase PFC + PLL | same family as PFC-1P-A |
| `BB-A / BB-A'` | AC-AC Buck-Boost (open loop, 4 switches) | two identical copies |
| `BB-B` | extended AC-AC Buck-Boost (8 switches, 4×RMS) | extension of BB-A |
| `EDU` | early teaching model (thyristors, Continuous powergui) | the only Continuous exception |
| `PFC-PR` | single-phase PFC with quasi-PR current loop | tuning testbed, lessons in rules.md §2.7 |

---

## 1. SCAN — power/frequency sweep platform ★ baseline

**Purpose**: power/frequency sweep test platform (paired with a 100kHz fast-loop MCU firmware project)
**Solver**: VariableStepAuto, StopTime=0.05; powergui Discrete, SampleTime=1e-8
**Power stage** (SPS):
- DC Voltage Source=200V
- 5×Mosfet (Ron=0.1, Rd=0.01, Vfd=0, Rs=1e5, Cs=inf, Measurements=on, all defaults)
- Series RLC Branch1=RC (R=0.0001, C=2200uF), Branch2=L (1mH), Branch3=C (1100uF), Branch5=L (13mH)
**Control**:
- Current inner loop: PID Controller (P=0.8, I=1, D=0, N=100, Ts=-1)
- Voltage loop (hand-written PI): Gain Kp=500 + DiscreteIntegrator gainval=12000 + Saturate [-190,190] + L di/dt feedforward=13e-3 + Voltage to duty=1/(2*200) + Duty center=0.5 + Duty limit=[0.02,0.98]
- Carrier: Carrier 100k sawtooth (rep_seq_t=[0 10e-6], rep_seq_y=[0 1]), RelationalOperator(>) comparison, NOT left/right complementary
- PWM Generator (DC-DC) Fsw=20000 kept as spare
- ZOH sampling: Iout/Iref/Slope ADC sample 100k (Ts=10e-6, 100kHz)
- Step test: Jump=0.1, Jump time ratio=0.02, Frequency Hz=100
**MATLAB Function 1 (sweep reference generator)**:
```matlab
function [y, slope_norm] = fcn(freq, jump, jump_ratio, t)
%#codegen
% MCU timing: 100 kHz PI, one target value held for 10 PI updates.
% jump_ratio = duration of EACH jump / waveform period.
persistent point_index hold_count previous_points
control_hz = 100000.0;
updates_per_point = uint32(10);
reference_update_hz = control_hz / double(updates_per_point);
base = 0.1;
rise = 0.6;
f = max(freq, 1.0);
points_d = 2.0 * round((reference_update_hz / f) / 2.0);
points_d = min(max(points_d, 4.0), 10000.0);
points = uint32(points_d);
... % triangle sweep + jump quantization (jump_points), full code in the source model
% Downstream gain/bias folded in: Iref = GainK*(y+Bias), GainK=10, Bias=-0.45
ref_gain = 10.0; ref_bias = -0.45; slope_gain = 10.0;
y = ref_gain * (y_target + ref_bias);
...
end
```
**MATLAB Function 2 (complementary gate signals)**:
```matlab
function [Q3, Q4] = fcn(t, scan_freq)
% 扫描频率切换
period = 1 / scan_freq;
t_mod = mod(t, period);
if t_mod < period / 2
    Q3 = 1;  % 正半周
    Q4 = 0;
else
    Q3 = 0;  % 负半周
    Q4 = 1;
end
end
```
**Logging**: ToWorkspace log_Io→PI_fast_Iout, log_Ir→PI_fast_Iref, log_PI_duty→PI_fast_duty, log_PI_voltage→PI_fast_Vcmd

---

## 2. INV-3P — three-phase inverter (~150 blocks, most complex)

**Solver**: VariableStepAuto, StopTime=0.1; powergui Discrete, SampleTime=50e-7
**Power stage**:
- DC Voltage Source=100V, C1=220uF, C2=R 1e-7 (shunt)
- 6×Mosfet (defaults), three-phase bridge
- L1/L2/L3 (R=20, L=1mH three-phase filter inductors), R1/R2/R3=5Ω load
**Control** (7×PID, all PI/Parallel/Forward Euler/N=100/D=0/Ts=-1):
- Current inner loops: P=30/I=20 ×4, P=40/I=15 ×2
- Outer loops: P=30/I=8 ×2
- Transform subsystems: Clarke (Ualpha/Ubeta), Park (Ud/Uq) ×2, inverse transforms ×2 (Fcn formulas in rules.md §2.3)
- Angle: Repeating Sequence (rep_seq_t=[0 1/50], rep_seq_y=[0 2*pi])
- SVPWM: MATLAB Function (7-segment, same template as PFC-3P)
- Carrier: Repeating Sequence (rep_seq_t=[0 1/20000/2 1/20000], rep_seq_y=[0 7200 0]) 20kHz
- Feedforward: Wl=2*pi*50*1e-3 ×4, WC=2*pi*50*220e-6 ×2
- Constants: Constant1=1/20000, Constant2=20, Constant3=30, Constant6=7200
- 6×Switch (Switcha/b/c1/2, threshold 0, u2>Threshold)

---

## 3. PFC-3P — three-phase boost PFC rectifier

**Solver**: VariableStepAuto, StopTime=0.1, MaxStep=1e-7; powergui Discrete, SampleTime=1e-6
**Power stage**:
- Three-phase sources UA/UB/UC (220*sqrt(2)V, phases 0/-120/-240)
- 3×Series RLC Branch (RL: R=0.1, L=2mH three-phase boost inductors)
- 6×IGBT//Diode (Ron=1e-3 default) bridge
- C1=4300e-6 (4.3mF), R1=16Ω
- Ground, Three-Phase V-I Measurement (LabelV=Vabc, LabelI=Iabc)
**Control**:
- 3×PID (PI): P=25/I=0.01 ×2, P=5/I=29.26 ×1, Ts=50e-9
- PID Controller4: P=15/I=0.00003512, Discrete-time, Ts=-1
- SVPWM: MATLAB Function (full code below)
- Carrier: Repeating Sequence (rep_seq_t=[0 1/20000/2 1/20000], rep_seq_y=[0 7200 0])
- Feedforward: Gain=2e-3*2*pi*50 ×2
- Constants: Constant2=220*sqrt(2), Constant5=1/20000, Constant6=7200, Constant7=700, Constant8=1/(220*sqrt(2))*pi
- Transforms: inverse-Clarke, Clarke (×2/3), Park ×2, inverse Park
- 6×Switch (Switcha/b/c1/2)

**SVPWM full code (standard template)**:
```matlab
function [Tcm1, Tcm2, Tcm3, sector] = SVPWM(Valpha, Vbeta, Udc, Tpwm, ARR)
    % 输出变量初始化
    Tcm1 = 0; Tcm2 = 0; Tcm3 = 0; sector = 0;
    % 扇区计算
    Vref1 = Vbeta;
    Vref2 = (sqrt(3) * Valpha - Vbeta) / 2;
    Vref3 = (-sqrt(3) * Valpha - Vbeta) / 2;
    if (Vref1 > 0), sector = 1; end
    if (Vref2 > 0), sector = sector + 2; end
    if (Vref3 > 0), sector = sector + 4; end
    % 扇区内合成矢量作用时间计算
    X = sqrt(3) * Vbeta * Tpwm / Udc;
    Y = Tpwm / Udc * (3/2 * Valpha + sqrt(3)/2 * Vbeta);
    Z = Tpwm / Udc * (-3/2 * Valpha + sqrt(3)/2 * Vbeta);
    switch (sector)
        case 1, T1 = Z;  T2 = Y;
        case 2, T1 = Y;  T2 = -X;
        case 3, T1 = -Z; T2 = X;
        case 4, T1 = -X; T2 = Z;
        case 5, T1 = X;  T2 = -Y;
        otherwise, T1 = -Y; T2 = -Z;
    end
    % 确保时间非负
    T1 = max(T1, 0); T2 = max(T2, 0);
    % 过调制处理
    if (T1 + T2 > Tpwm)
        T1 = Tpwm * T1 / (T1 + T2);
        T2 = Tpwm * T2 / (T1 + T2);
    end
    % 零矢量分配时间
    ta = max((Tpwm - (T1 + T2)) / 4, 0);
    tb = ta + T1 / 2;
    tc = tb + T2 / 2;
    % 输出调制信号
    switch (sector)
        case 1, Tcm1 = tb; Tcm2 = ta; Tcm3 = tc;
        case 2, Tcm1 = ta; Tcm2 = tc; Tcm3 = tb;
        case 3, Tcm1 = ta; Tcm2 = tb; Tcm3 = tc;
        case 4, Tcm1 = tc; Tcm2 = tb; Tcm3 = ta;
        case 5, Tcm1 = tc; Tcm2 = ta; Tcm3 = tb;
        case 6, Tcm1 = tb; Tcm2 = tc; Tcm3 = ta;
    end
    % 调制信号归一化
    Tcm1 = 2 * Tcm1 / Tpwm; Tcm2 = 2 * Tcm2 / Tpwm; Tcm3 = 2 * Tcm3 / Tpwm;
    % 映射到 ARR 范围
    Tcm1 = max(min(Tcm1 * ARR, ARR), 0);
    Tcm2 = max(min(Tcm2 * ARR, ARR), 0);
    Tcm3 = max(min(Tcm3 * ARR, ARR), 0);
end
```

---

## 4. PFC-1P-A / PFC-1P-B — single-phase PFC family

**⚠️ Field finding: PFC-1P-A diverges when simulated as-is** (Uo stuck at -28V, Iin rms 700A, modulation goes NaN) — its topology/parameters have issues, so it is **not a working reference**; use it only for block-structure reference (4-switch topology + bipolar modulation + uin feedforward idea). Its modulation structure: `Sum2 = uin feedforward + inner-loop PI + WL`, `G1=(Sum2>=carrier)`, `G3=(-Sum2>=carrier)`, two complementary pairs (NOT) driving the 4 switches. 4-switch topology (from XML): IGBT1=D↔E, IGBT2=B↔E, IGBT6=C↔D, IGBT7=C↔B, where B=Uin.lconn, D=Uin.rconn via sensing inductor, C/E=DC bus (C1 across).

**PFC-1P-A**: 63 blocks, StopTime=0.5, powergui Discrete 1e-7
- Uin 220*sqrt(2)V/50Hz → L (R=16, L=10mH) → 4×IGBT//Diode (Ron=1e-3) → C1 (48mF) → R (16Ω)
- 2×PID: P=6.6543/I=12, P=12/I=5, Ts=2e-5 (50kHz)
- PID Controller4: P=2/I=0.00003512, Discrete
- Carrier 50kHz: Repeating Sequence (rep_seq_t=[0 1e-5 2e-5], rep_seq_y=[0 1 0]) ×2 + RelationalOperator ×2
- Constant1=400 (output voltage reference), Constant3=2*pi, WL=1e-3*100*pi feedforward
- Trigonometric Function + Mod (sine phase), Gain=-1, Gain1=1/20
- Subsystem2/9 (not fully explored, likely transforms/protection)

**PFC-1P-B**: 50 blocks, StopTime=0.5, powergui Discrete 1e-7 (simplified PFC-1P-A)
- Same family topology (Uin → RL 0.01+1mH → 4 IGBT → C1 48mF → R 16Ω)
- 2×PID as above (2e-5) + PID Controller4
- **PLL block**: Fmin=50, Par_Init=[0,50], ParK=[180,3200,1], TcD=1e-4, MaxRateChangeFreq=12, FilterCutOffFreq=25, Ts=1e-6, AGC=on
- Carrier 50kHz ×2, WL=1e-3*100*pi, Constant1=400, Display
- Note: the companion firmware's 400V Uo reference matches this

---

## 5. BB-A / BB-B — Buck-Boost family

**BB-A (= BB-A', identical copy, 42 blocks)**:
- AC Voltage Source 24*sqrt(2)V/50Hz → 4×Mosfet + 4×PWM Generator (DC-DC) (Fsw=20000)
- Series RLC: L=1mH, R=50Ω, C=30uF, shunt R=1e-5
- Constant=1, Constant4=1, Constant6=0.6 (duty 0.6), Gain=1/30, Gain1=2, Gain2=2
- 4×Switcha (threshold 0), NOT ×2, Multimeter (L=3)
- powergui Discrete 50e-7, StopTime=2
- Open loop (duty-driven, no feedback)

**BB-B (extended, 51 blocks)**:
- 8×Mosfet, 4×PWM Generator (Fsw=20000), 4×RMS (TrueRMS=on, Freq=50)
- 2×Current Measurement + 2×Voltage Measurement, 4×Display
- Constant=0.5, Constant1=1, Gain=1/30, Gain1/2=2
- powergui Discrete 50e-7, StopTime=0.5
- Sampling time: symbolic `Ts` (referenced 78×, must be defined in the workspace); sps.TimeStep ×2

---

## 6. EDU — early teaching model

- **powergui Continuous** (the only exception), SampleTime=50e-6, StopTime=0.2
- Three-phase sources A/B/C (220V, phases 30/-90/-210) → Linear Transformer (250e6/20e3, two-winding, pu) → 9×VT thyristors (Ron=0.01, Rd=.01, Rs=5, Cs=1e-6) + 9×VD diodes (Ron=0.001, Vf=0.8, Rs=500, Cs=250e-9)
- PID (P=6.8/I=2), 4×DiscretePulseGenerator, Repeating Sequence (20kHz ±20 triangle), Mosfet, several RLC loads (20Ω / 1Ω+10mH / 2.5Ω)
- C1/C2/C3 capacitors (1mF/32mF/10uF), L1..L4 inductors (1mH/10uH/23mH/10nH)

---

## 7. Family map

```
Buck-Boost family:  BB-A ≡ BB-A' (copy) → BB-B (extended)
Single-phase PFC:   PFC-1P-A → PFC-1P-B (simplified + PLL)
Three-phase PFC:    PFC-3P-A ≡ PFC-3P-B (identical copies)
Three-phase inverter: INV-3P (standalone; SVPWM shares the PFC-3P template)
Sweep platform:     SCAN (newest, style-defining)
Teaching:           EDU (earliest, Continuous)
PR testbed:         PFC-PR (single-phase PFC + quasi-PR current loop)
```
