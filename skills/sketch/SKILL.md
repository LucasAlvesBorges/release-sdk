---
name: sketch
description: Explore a React UI idea through 2–3 runnable, navigable variants before choosing an implementation direction.
---

# `/release:sketch`

Use this before a React web UI decision is committed. It creates a local, runnable exploration;
it does not alter production routes, auth, APIs, backend code, roadmap, or phase cursor.

## Usage

```text
/release:sketch <idea> [--quick]
/release:sketch [frontier]
/release:sketch --wrap-up [sketch-id]
```

`--quick` skips direction intake when the prompt already fixes the important design choices.
Without an idea, or with `frontier`, inspect the existing sketch manifest and propose a small,
relevant next design question. Do not build any proposal until the user chooses it.

## Start

1. Create `.release-planning/sketches/` and `MANIFEST.md` when absent; this does not require
   `/release:init`. Preserve existing rows, variants, rationale, and selections.
2. For an idea, ask only the unanswered questions that affect hierarchy, interaction, responsive
   behavior, or accessibility. Keep the question narrow enough to compare in one sketch.
3. Read the closest existing React route/component, `package.json`, style/token source, and the
   existing preview/test setup. Reuse installed versions, primitives, providers, aliases, and CSS
   conventions. At least one variant must fit that system.
4. Record the target, question, design direction, source paths, and `status: pending-review` in
   the manifest before building. Use the next `NNN-slug` directory.

## Build a React sketch

Create `.release-planning/sketches/NNN-slug/` with:

```text
README.md                 # question, variants, rationale, preview command/URL, status
src/                      # TSX entry, variant components, local typed fixtures, styles
index.html                # Vite bootstrap when an isolated entry is needed
```

Keep fixture/data code separate from components. Use TypeScript and React TSX; never substitute
static HTML, CDN scripts, Babel-in-browser, or `file://` instructions. Reuse project components
only when imports, aliases, CSS, and required providers work in the isolated preview. Do not mount
whole-app providers or make real requests: fixtures and interactions stay local.

Build 2–3 alternatives with the same meaningful content and task. They must differ in information
hierarchy, layout, or interaction, rather than palette-only changes. Label A/B/C and preserve a
short rationale for each. A dashboard, fleet view, or trip planner may use realistic Portuguese
labels and Brazilian dates/currency when that is the domain; do not make Hubus-specific content a
general requirement.

The preview supplies a variant selector and viewport controls outside the product UI. Use an iframe
or real browser resize so responsive media queries see the actual viewport. Provide desktop and
mobile layouts, visible keyboard focus, semantic labels, and working local interactions. Include
loading, empty, and error states when the idea has asynchronous or collection behavior.

Use an installed Vite harness, sandbox, or Storybook first. Otherwise create the smallest isolated
Vite React TypeScript entry within the sketch folder, using the project's package manager and only
dependencies needed to run it. Keep the entry/config separate from the production app. Use the
existing dev runner and runner-visible paths when the project runs in a container. Run the exact
preview command, verify the observed local URL, and write both into `README.md`. If no runnable
React setup is available and it cannot be installed,
state that limitation plainly; never present an unrun preview as runnable.

Run the available focused type/build checks for the sketch. When browser tools are available,
inspect every variant at desktop and mobile sizes and exercise the main interaction and keyboard
navigation; fix failures before presenting. Report any checks that could not run. A responding
server alone does not verify that TSX, imports, styles, or interactions work.

## Review and selection

Present the command and comparison question, then leave the sketch `pending-review`. Browser state
or `localStorage` may remember a preview selection, but it is never project approval. Only after
the user explicitly selects a variant may you update `winner`, status, and manifest decisions.
Keep A/B/C. If the user combines pieces, add a named synthesis variant with its source variants and
rationale, then request explicit approval for that new variant.

`MANIFEST.md` tracks each sketch: ID, question, status, A/B/C (and synthesis) rationale, winner,
approved decisions, source paths, and preview command/URL. It is a history, not a roadmap artifact.

## Wrap-up

`--wrap-up [sketch-id]` reads only sketches with explicit approved selections. It writes or updates
`IMPLEMENTATION-HANDOFF.md` in the sketch directory and `.claude/skills/<project>-design/SKILL.md`.
Both are self-contained: approved decisions, rejected or open choices, component/style/fixture
source paths, responsive and accessibility notes, exact preview command, and extraction steps for
a future React implementation. Keep selected TSX in the sketch and reference it; copy a source only
when the skill would otherwise be incomplete. Preserve prior approved decisions for other sketches
when updating the project design skill. Do not edit root guidance, production code, or roadmap state, and do not
silently accept a pending browser selection. If no approved sketch matches, report that the user
must select one first.

## Completion

Report sketch path, status, variant comparison, and verified preview command/URL. Suggest
`/release:ui-phase` only after an explicit winner exists; the later phase owns production design
and implementation.
