---
name: model-router
description: Classify the current coding task and recommend the optimal model tier and thinking level from the user's homelab setup. Use when starting a new task, when the current model seems underpowered, or when the user asks which model to use. Helps minimize cost by routing small tasks to free local models and reserving cloud models for complex work.
---

# Model Router

## Available Tiers

| Tier | Model(s) | Best For | Context | Cost |
|------|----------|----------|---------|------|
| **T0 — Free/Fast Local** | `local/qwen2.5-coder-7b`, `local/qwen3-coder-next-32k` | Quick fixes, 1-liners, regex, simple refactors, explaining a function | 32K / 4K out | $0 |
| **T1 — Capable Local** | `local/qwen3-coder-next` (default), `local/qwen3.6-35b`, `local/qwen3-30b` | Daily features, multi-file edits, tests, docs, debugging | 128K / 8K out | $0 |
| **T2 — Cheap Cloud** | `zen/deepseek-v4-flash-free` | Fallback when local is slow/down; slightly better reasoning than T1 | 128K / 8K out | ~$0 |
| **T3 — Capable Cloud** | `zen/claude-sonnet-4-6`, `zen/gpt-5.1` | Image analysis, security review, standard tricky bugs, multi-file refactors | 128K–200K / 8K out | Low |
| **T4 — Advanced Cloud** | `zen/kimi-k2.5` | Complex architecture, design decisions, deep reasoning, novel problems | 128K / 8K out | Low–Mid |
| **T5 — Best Cloud** | `zen/claude-opus-4-7` | Massive refactors, hardest novel problems, deep cross-project reasoning, when T4 isn't enough | 200K / 8K out | Higher |
| **T6 — Long Context** | `zen/gemini-3.5-flash` | Huge codebase ingestion (1M context), massive documents, long-context analysis | 1M / 8K out | Low |

## Thinking Level Guide

Use this alongside tier selection:

| Level | When to Use |
|-------|-------------|
| **off** | Trivial, well-scoped tasks. Fastest, cheapest. |
| **low** | Minor feature, clear requirements. |
| **medium** (default) | Standard coding work, some ambiguity. |
| **high** | Complex design, trade-offs, debugging mystery. |
| **xhigh** | Reserved for T4 models on truly novel/hard problems. |

## Decision Process

Analyze the user's request against these criteria:

1. **Scope**: How many files/lines will this touch?
2. **Complexity**: Is this a known pattern or novel problem?
3. **Context needed**: Do we need to read 10+ files or a huge doc?
4. **Urgency**: Does the user need an answer in 5 seconds or 5 minutes?
5. **Risk**: Could a wrong answer break production?

Then recommend:
- **Tier + specific model**
- **Thinking level**
- **Brief justification**

## Output Format

Always respond with a clear recommendation block:

```
[MODEL ROUTER]
Task type: <classification>
Recommended: <model-id> + thinking=<level>
Rationale: <1-2 sentences>
Current: <what model is currently active>
Action: <stay, switch, or ask for clarification>
```

If the current model is already appropriate, say so and proceed with the task.
If a switch is recommended, tell the user exactly how:
- Press `Ctrl+P` to cycle enabled models
- Or type `/model` to pick interactively
- Or type `/settings` to change thinking level

## Escalation Rules

- If on T0/T1 and the task involves **images**, recommend T3+ (those support image input).
- If on T0/T1 and the user asks for **architecture/design review**, recommend T4 (Kimi) or T3 (Sonnet/GPT).
- If on T0/T1 and the task keeps failing after 2 attempts, recommend T2 or T3.
- If T4 (Kimi) is struggling on a truly novel or massive problem, escalate to T5 (Opus).
- If on T3+ and the task is trivial (1 file, <20 lines), suggest dropping to T1 to save cost.
- If **1M+ tokens** of context are needed, recommend T6 (Gemini).
