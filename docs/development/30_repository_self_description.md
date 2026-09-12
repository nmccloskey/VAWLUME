# Repository self-description

> **Audience and status.** This is an internal conventions document, published
> so the project's development practices are inspectable. It is not a guide to
> *using* VAWLUME — for that, see the
> [prototype usage guide](../usage/01_prototype_usage_guide.md).

## 1. The principle

**VAWLUME's software state is authoritative. Its documentation describes that
state rather than maintaining a second, manually synchronized version of it.**

Every literal a document publishes about the repository — how many tests exist,
which demonstrations ship, what version the schema carries, which configuration
directories hold artifacts — is a copy of a fact that already lives somewhere
authoritative. A copy nothing verifies drifts, and drifted documentation is
worse than absent documentation because it still reads as true.

This document defines how such claims are written, which ones are checked, and
what the check does not cover.

## 2. Claim classes

Four kinds of statement appear in the repository's documentation. They are
handled differently.

### Derived fact

Something computed from the repository on demand. The suite size, the shipped
demonstrations, the schema version triple, the configuration tree, the MATLAB
packages, the Markdown documents.

`tools/repository_inventory.m` computes these. It is the answer to "how many
tests are there?" — not a sentence in a document.

### Current-state claim

Published text asserting a present repository fact: *the schema is `0.7-draft`*.

**A current-state claim is permitted only when
`tools/check_repository_self_description.m` verifies it.** Adding one that
nothing checks reintroduces exactly the failure this layer exists to prevent.

### Historical claim

Published text recording a past checkpoint: *introduced at schema version
`0.5-draft`*, *the regression floor leaving Phase 7 was 329 tests*.

Historical claims are frozen and exempt. They are true statements about a moment
that has passed, and correcting them to match today would destroy the record.

A historical claim must be recognizable as one. Two mechanisms mark it:

- **Location.** Everything under `docs/design/` is the frozen design-record
  layer — contracts as written, audits as performed. It does not describe the
  repository as it stands today.
- **Marker phrase.** Elsewhere, a paragraph is read as historical when it
  contains `Introduced at`, `Added at`, `Pre-existing`, `regression floor`,
  `exit state`, or `historical record`.

Marking is paragraph-scoped, so a marker anywhere in the paragraph covers every
literal in it. Prefer the established phrasing — `Introduced at schema version
X (PRAGMA user_version = N)` — over inventing a new marker.

### Qualitative description

Prose that stays true across ordinary change: *the demonstrations under
`examples/`*, *every shipped demonstration creates every input it needs*.

**Prefer this wherever the exact number carries no reader value.** "The nine
demonstrations under `examples/`" told the reader nothing that the list of nine
names immediately below it did not, and cost a hand edit every time the set
changed. The count was removed; the enumerated names stayed, and the check
verifies those against the directory.

The reverse is also true. Some literals must stay literal because a reader
acting on them needs the exact value — the schema version and its
`PRAGMA user_version` are the clear case. Those are kept and verified.

## 3. Version namespaces

`X.Y-draft` is a shape shared by four independent version namespaces. Confusing
them produces false failures, and a check that reports false failures gets
ignored.

| Namespace | Where it lives | Current-state claim? |
|---|---|---|
| Relational schema | `schema_info.schema_version`, `PRAGMA user_version`, `schema/schema.sql` header | **Yes** — checked |
| Profile language | `profile_schema_version` in JSON profiles | No — the loader validates it |
| Intermediate representation | `ir_schema_version` | No — the IR layer validates it |
| Alignment manifest | `manifest_schema_version` | No — alignment intake validates it |

The discriminator is `PRAGMA user_version`, which belongs to the relational
schema alone. Hence the authoring convention:

> **A published relational schema version states its `PRAGMA user_version`
> alongside it.**

This is what makes the claim findable. A paragraph naming `user_version` is read
as a relational-schema claim and checked; one that does not is left alone.

## 4. What the check verifies

`check_repository_self_description` runs seven checks.

| # | Check | Authority |
|---|---|---|
| 1 | The schema version is internally coherent | `schema.sql` header, the `schema_info` seed, and `PRAGMA user_version` must agree |
| 2 | Published relational-schema versions are current | §3; historical claims exempt per §2 |
| 3 | The demonstrations named in the README and the usage guide are exactly those in `examples/` | Checked in both directions: an undocumented example and a documented non-example both fail |
| 4 | Every demonstration is named by an integration test | Both documents claim this |
| 5 | Every configuration directory holding an artifact is named in `config/README.md`, and every `config/` path the documentation names exists | |
| 6 | Every relative Markdown link resolves | A dead link is a stale claim in the same sense a stale count is |
| 7 | Neither the README nor the usage guide states a literal suite size | §2: this is a derived fact, not prose |

Check 7 is a guard rather than a verification. The hand-maintained test count was
edited by hand in five consecutive itineraries and verified by nothing; check 7
is what stops it coming back.

## 5. Running it

```matlab
addpath("tools")
repository_inventory                  % what the repository holds
check_repository_self_description     % whether the documentation still says so
```

Both print a report when called without an output argument. The check raises
`vawlume:repository:SelfDescriptionStale` on failure; with an output argument it
returns a report struct and raises nothing.

`tests/unit/test_repository_self_description.m` wraps the check, so it also runs
inside the full gate. The cheap form is:

```text
matlab -batch "addpath('src'); assertSuccess(runtests('tests/unit/test_repository_self_description.m'));"
```

**This belongs to the ordinary per-itinerary validation tier**, not to the phase
gate. It is non-executing: it discovers tests without running them, opens no
database, writes nothing, and finishes in seconds. That is the whole point —
a check reserved for phase boundaries would have caught these drifts exactly
where they were already being caught.

See [`02_development_workflow.md`](02_development_workflow.md) for how the tiers
fit together.

## 6. What it does not do

It is a self-description check, not a correctness check. It does not:

- run any test, or say anything about whether the suite passes;
- open a database, apply the schema, or validate any JSON profile;
- verify prose beyond the literals listed in §4 — a paragraph can describe
  behaviour VAWLUME does not have and pass every check here;
- verify anything under `docs/design/`, which is frozen by §2;
- check version literals in the profile-language, IR, or manifest namespaces,
  which belong to the loaders that own them;
- check anchors within Markdown links, only that the target file exists;
- distinguish tracked files from untracked ones. It walks the filesystem, so an
  untracked stray `.md` is inventoried like any other. Run it on a clean tree.

Adding a check is cheaper than adding a convention. When a new literal about the
repository is worth publishing, verify it here; when it is not worth verifying,
that is the signal to write it qualitatively instead.
