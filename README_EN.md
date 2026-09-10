# Simulink Power Electronics Skill — Modeling Rules for the Black Block Library (SPS)

**English | [简体中文](README.md)**

> A power-electronics modeling rulebook reverse-engineered from 10 real, working Simulink models, written for the **Simscape Electrical Specialized Power Systems library (SPS — the "black block" library, named after its black module icons)**. It also works as a skill for AI agents (Claude, WorkBuddy, etc.) that build simulations.

![Single-phase inverter example](docs/images/example_single_phase_inverter_spwm.png)
*A single-phase SPWM inverter model built with these rules*

![PMSM FOC example](docs/images/example_pmsm_foc.png)
*A three-phase PMSM FOC model built with these rules (SPS permanent-magnet synchronous machine + SVPWM)*

## Why "black block library"

In the Simulink Library Browser, every electrical component under **Simscape Electrical → Specialized Power Systems (SPS)** has a black icon — `powergui`, `Mosfet`, `IGBT//Diode`, `Series RLC Branch`… instantly distinguishable from the pale blocks of the core Simulink library. The power stage in this playbook **only uses this black library**; control logic only uses core Simulink blocks. All 10 source models follow this without exception — it's an iron rule.

## What this is

This is not a textbook of generic best practices. It is a **measured playbook**:

- Every rule is tagged with an anonymized source model; every parameter comes from a real model's mask values, not guesswork
- Covers: a fixed 7-step modeling workflow, hand-built carrier-comparison PWM, a field-measured PI tuning table, complete 7-segment SVPWM code, Clarke/Park transform templates, quasi-PR controller tuning lessons, solver/sampling-time configuration, naming conventions, and safety floors
- Especially useful for making AI agents produce power-electronics simulations with a consistent style and credible parameters

## Topologies covered

| Topology | Code | Highlights |
|---|---|---|
| DC-DC power/frequency sweep platform | SCAN | 100kHz fast loop, hand-written PI + feedforward, test-signal generation |
| Three-phase two-level inverter | INV-3P | PI double loops + dq decoupling + SVPWM |
| Three-phase boost PFC rectifier | PFC-3P | IGBT bridge, 50e-9 control sampling |
| Single-phase 4-switch PFC | PFC-1P-A/B | bipolar modulation, uin feedforward, PLL |
| AC-AC Buck-Boost | BB-A/B | open-loop duty, PWM Generator (DC-DC) |
| Quasi-PR current-loop testbed | PFC-PR | Tustin-discretized PR + anti-windup + feedforward lessons |
| Early teaching model | EDU | thyristors, the only Continuous exception |

## Quick start

### As an AI agent skill (recommended)

Copy the whole folder into your agent's skill directory, e.g. for WorkBuddy:

```
~/.workbuddy/skills/power-simulink-rule/
```

From then on, asking the agent to "build a PFC / inverter / Buck-Boost simulation" makes it follow this rulebook. Claude Code and other tools that support the SKILL.md format work the same way.

### As a human-readable rulebook

Read in this order:

1. [`SKILL.md`](SKILL.md) — core rules at a glance (7-step workflow, control templates, naming, parameters, safety floors)
2. [`references/rules.md`](references/rules.md) — detailed spec, every rule tagged with its source
3. [`references/library-guide.md`](references/library-guide.md) — full block list for SPS + core libraries, and the forbidden list
4. [`references/models-analysis.md`](references/models-analysis.md) — per-model measured evidence for all 10 models (the evidence chain)

The companion script [`scripts/extract_model_params.m`](scripts/extract_model_params.m) extracts solver/mask parameters from any Simulink model — handy for auditing your own models:

```matlab
>> extract_model_params('your_model_name')
```

## Rule cheat sheet (20-second version)

- **Place `powergui` first, always Discrete** (SampleTime 1e-7~50e-7)
- Power stage only from SPS; control only from core Simulink; nothing else
- PWM: prefer hand-built carrier comparison — `Repeating Sequence` carrier (amplitude = MCU ARR, e.g. 7200) + `Relational Operator(>)` + `NOT` for complementarity
- PI always via `PID Controller` (PI/Parallel/Forward Euler/N=100); inner loop explicit sampling, outer loop -1 (inherit)
- Write parameters as expressions, not pre-computed numbers: `24*sqrt(2)`, `1/20000`, `2e-3*2*pi*50`
- Duty clipped to [0.02, 0.98]; every control output goes through `Saturate`
- Current sensing via milliohm shunts (1e-5~1e-7) + isolated measurement
- Comments are colloquial Chinese explaining *why*

## ⚠️ Honest disclaimer

**This skill comes from the author's daily personal practice. It has been used personally but has NOT been systematically tested or validated.**

- The author finds it very pleasant to work with — the **control side (PI/PWM/SVPWM/PR) is high quality**
- Known weakness: **model wiring can be messy** (heavy From/Goto signal routing; aesthetics were not a goal)
- Measured parameters come from the author's own projects (voltage/power levels may not match yours) — re-derive them for your own circuit before copying
- One single-phase PFC source model (PFC-1P-A) diverges when simulated as-is; the rulebook honestly flags it as "structure reference only"

## Requirements

- MATLAB R2024b (other releases probably work but are unverified; the `DiscreteIntegrator` gain parameter was named `GainValue` in older releases)
- When used as an agent skill, you need an agent environment that can drive MATLAB/Simulink (e.g. a MATLAB MCP server)

## Repository layout

```
power-simulink-rule/
├── SKILL.md                        # core rulebook (agent entry point)
├── references/
│   ├── rules.md                    # detailed rules (each tagged with source code)
│   ├── library-guide.md            # library selection + compliance-check code
│   └── models-analysis.md          # measured evidence from 10 models (anonymized)
├── scripts/
│   └── extract_model_params.m      # model parameter extraction tool
├── docs/images/                    # example model screenshots
├── LICENSE                         # MIT
├── README.md                       # Chinese readme
└── README_EN.md                    # this file
```

## License

[MIT](LICENSE) © 1841220388zzzcccxxx-star
