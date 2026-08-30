# Adopting DeepSeek Harness principles into pi

Status: **planning / not yet implemented**. Research done against the DeepSeek
Harness (`dsh`) developer-preview source cloned to `~/examples/deepseek-harness`
(built on the Cordis plugin framework, "everything is a plugin").

This note records (1) the `dsh` principles we consider worth adopting, (2) where
pi already embodies or deliberately refuses each, and (3) a phased feature plan
split into upstream-ready core changes vs. thin extension packages. The through
line: pi's identity is *"aggressively extensible, don't dictate"*, so most of
what's worth borrowing is adopted as **an extension package + repo discipline**,
not a fork.

## Part 1 — DeepSeek Harness core principles

1. **Everything is a plugin — no privileged core.** Model adapter, tool
   registry, session log, and even the agent loop are all plugins mounted on a
   shared `ctx`. You extend by mounting a plugin *beside* the others.
2. **Registrations are reversible effects.** Contributions go through
   `ctx.effect()` / `ctx.on()` and return disposers that unwind on
   reload/unload — what makes hot reload and teardown safe.
3. **Capability seams: Service Definition / Provider / Consumer.** A swappable
   capability defined by an interface, an implementation, and a model-facing
   Consumer. One provider swap changes the whole product — e.g. filesystem +
   subprocess + terminal + LSP share one execution world.
4. **Model-visible ⟺ logged.** The session log is the single source of the
   context the model sees; anything reaching a model request must be
   reconstructable from the log (a runtime invariant asserts it). Fork, resume,
   telemetry, persistence, and context projection all derive from the stream.
5. **Three-domain event taxonomy.** Session events (durable facts), agent events
   (`agent/*`, live work in flight), capability events (policy/adapters).
6. **Explicit turn/step pipeline with interception points** and waterfall
   semantics (listeners must call `next()` to delegate).
7. **Composition by ordered layers: profiles + bundles + patches.** A running
   harness is a plugin tree built from ordered config layers, each row
   patchable by ID; `web`/`headless`/`sdk`/`acp` are just profiles.
8. **Runtime invariants registry (`ctx.invariants`).** Package-owned checks
   asserting on authoritative event streams or mutable data, with package-
   attributed failures.
9. **AI-native engineering discipline.** AGENTS.md/agent-notes, strict prose
   rules, and **keyless recorded-session snapshot replay** — each model-visible
   change must update a replayed-session snapshot.
10. **Safety as a posture.** Least privilege; sandbox/approval/permission-
    presets are swappable capability seams, never the sole security control.
11. **First-class capabilities pi deliberately omits** — sub-agents, plan mode
    (as *logged state*), approval/policy presets, goals, scheduled reminders,
    background jobs, sandboxing.

## Part 2 — Map vs. pi

| `dsh` principle | pi today | Verdict |
|---|---|---|
| Everything is a plugin | Extension-first philosophy; tools *can* be replaced entirely; system prompt overridable | Aligned in spirit, core still privileged |
| Reversible effects | `session_shutdown` + `/reload`, no effect-disposer contract | Partial — gap |
| Capability seams | Individual tools, no provider-swap abstraction | **Biggest gap** |
| Model-visible ⟺ logged | JSONL session IS the source; full history preserved | Mostly true — formalize |
| Three-domain events | Rich lifecycle events, not formally split | Partial |
| Explicit pipeline + interception | `context`, `before_provider_request`, `tool_call`, `tool_result` | Aligned |
| Composition by layers/patches | packages + settings (global/project), no patch rows | Gap — a package can fix |
| Runtime invariants | none | Gap |
| Snapshot/replay regression | sessions are JSONL; no replay harness | Gap — tooling |
| Sub-agents, plan, approval, goals, jobs | Explicit "no — build with extensions" | **Skip as core** |

Core tension: `dsh` bakes capabilities in as swappable seams; pi's philosophy
is "never dictate, ship extensions." Most of what's worth adopting fits as an
extension package + repo discipline.

## Part 3 — Phased plan (what we adopt)

### Phase 0 — Foundation (cheap, process-only, biggest leverage)
- **A. Reversible-effect/SDK-disposer contract (principle 2).** Add a first-class
  `ctx.effect(register)` to the extension SDK returning a disposer, auto-unwound
  on `session_shutdown`/`reload`. *Surface:* SDK + docs. *Effort:* S–M, additive.
  (Full plugin-tree unload = larger rework; defer.)
- **B. "Model-visible ⟺ logged" invariant + docs (principle 4).** Formalize the
  existing JSONL source-of-truth: guideline + small invariant that throws if a
  message reaching a provider call isn't reconstructable from the log. *Effort:* S.

### Phase 1 — Capability seams (principle 3; the defining architectural bet)
- **C. `capability-seam` pattern library/package** implementing
  SD/Provider/Consumer triad. First seam: **execution/world** — group `bash`,
  `subprocess`, `terminal` (and `fs`) behind one swappable backend so pointing
  them at a remote sandbox moves all together (the "one provider swap changes
  the whole product" win). *Surface:* extension package, opt-in, no fork.
  *Effort:* M–L. Also the home for opt-in **sandbox / permission-presets /
  approval policies** as consumer/policy plugins — consistent with pi's
  "build it with extensions."

### Phase 2 — Discipline the model-visible surface (principle 9)
- **D. Recorded-session replay + snapshot regression harness.** Record a
  keyless transcript via `/export` JSONL, replay through a fixed model in
  `--mode json`, diff emitted `assistant`/`tool` sequence vs. committed
  snapshot. Adopt here; offer upstream. Maps 1:1 onto pi's session format.
  *Effort:* M, low risk (tooling-only).
- **E. Invariants registry.** Lightweight `ctx.invariants` with package-
  attributed `fail()`; combined with D makes model-visible changes verifiable.
  *Effort:* M.

### Phase 3 — Optional/aspirational (defer, higher risk)
- **F. Profiles + bundles + patch layers (principle 7).** Ordered config rows
  with ID-targeted overrides across project/global/user layers. *Effort:* L;
  reconsider after Phase 1 proves out.
- **G. Three-domain event taxonomy (principle 5).** Largely documents/naming
  cleanup of existing events. *Effort:* S–M.

### Deliberately NOT adopted (core)
- First-class **sub-agents, plan mode, approval popups, goals, scheduled
  reminders, background jobs** as core. `dsh` builds these in; pi's stated
  philosophy is "no X — build it with an extension." Adopting as core would
  violate pi's identity. The Phase-1 seam package gives an *opt-in* path,
  which is the correct middle ground.
- **Open-sourcing the loop itself** — pi isn't built on Cordis; the extension
  surface achieves ~80% of the benefit without a rewrite.

## Next steps
1. Start with **Phase 0 (A + B)** — smallest, safest, easy upstream PRs to pi.
2. Prototype **Phase 1 (C)** as a local pi package — the defining bet; validate
   against real pi before committing to Phase 3.

Deliberately paused here per user request; resume by starting Phase 0.

## Appendix — Append-only to prevent cache misses (verified + estimated)

Research request: verify `dsh`'s "append-only to prevent cache misses" principle
against the source, and estimate how hard it would be to add to pi.

### Verified: it is a real, documented `dsh` principle

Three concrete mechanisms in the actual source:

1. **Append-only session log is the sole source of context.** `core/session`
   owns "the append-only `SessionEvent` log." From `docs/architecture.md`: *"The
   session log is the source of the context the model sees… Anything that
   reaches a model request must be reconstructable from the log."*
2. **Deterministic, frozen projection with per-node caching.**
   `Session.deriveMessages()` folds the log into the model-facing `Message[]`
   via a pure `deriveEventMessage` per node — "cached (each surface node
   projected once, when first seen)… deep-frozen, so mutating logged history
   through a projection is unrepresentable." This is what makes the request
   prefix **byte-stable across turns** (turn N+1 = turn N + appended tail).
3. **The enforced "KV Cache effect" doc contract.** Every `dsh` package README
   must state its cache effect — "distinguish append-only growth, a stable
   repeated prefix, replacement of earlier request tokens, and an independent
   model request" — and a **verifier** enforces it. `app-boot` keeps one stable
   line at the head, "before per-request content, so it does not invalidate the
   cache across turns."

So the principle = append-only storage + a deterministically derived, frozen,
prefix-stable request + doc discipline that keeps the head stable.

### Where pi already is

- **Append-only JSONL session** — matches point 1 almost exactly
  (`buildContextEntries()` walks leaf→root deterministically from the log).
- **Provider cache awareness** — pi tracks cache hit/write (`R`/`W`/`CH` in
  footer), supports `PI_CACHE_RETENTION`, and disables prompt-cache writes for
  compaction and branch-summary requests (unlikely to be reused).
- **Deterministic context assembly** — ✅ in the happy path the prefix is stable.

Missing (the actual adoptable bit):

- **No stable-prefix invariant.** The `context` event lets extensions
  filter/reorder/prune messages; `before_agent_start` can rewrite the system
  prompt; the tool set can change. Any rewrites the request head and silently
  blows the cache, with no contract or warning.
- **No projection caching** (pi rebuilds context per call — a compute concern,
  not a model-cache one; dsh's frozen per-node cache is the stronger version).
- **No "KV Cache effect" doc discipline / verifier** — the enforcement layer.
- **Compaction inherently breaks the prefix** by design (lossy summarization)
  — accepted in both, but dsh's stable-head protection contains the damage.

### Difficulty estimate

The append-only *log* is already done; what's missing is the guarantee +
instrumentation layer, not a rewrite.

| Deliverable | Surface | Effort | Risk |
|---|---|---|---|
| Cache-miss diagnostic + stable-prefix warning (diff each turn's request head vs. previous; flag rewrites) | Extension/package (no fork) or small upstream PR | ~0.5–1 day | none |
| Documented stable-head convention + repo verifier ("KV Cache effect" discipline, adapted for extensions + compaction) | Docs + lint/verify script | ~1 day + ongoing | none |
| Frozen deterministic projection cache (mirror `dsh` `deriveMessages`) | Upstream session/context manager | ~1–2 days, isolated | low |
| Soft stable-prefix guarantee for the head (system prompt + tool schemas, versioned/frozen) | Upstream request assembly | ~2–3 days | medium |
| Restrict/curtail the `context`-event rewrite (the cache-hostile surface) | Upstream extension semantics | breaking; several days + community impact | high |

**Bottom line.** A faithful, enforced core adoption is roughly **1–2 weeks**
upstream (plus testing). An ~80% win that respects pi's "don't dictate"
philosophy — append-only log + cache diagnostic + stable-head convention +
verifier — is **a few days**, mostly a package plus a small PR, zero
backward-compat risk. Avoid changing `context` event semantics; instead add a
`prefixStable` flag + telemetry so cache-hostile extensions are *measurable
rather than forbidden*.
