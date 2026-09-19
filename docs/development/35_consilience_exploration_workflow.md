# Extractor-consilience exploration workflow

> **Audience and status.** Implementation-facing documentation for the
> poster-stage exploratory workflow in `src/+vawlume/+eda/`. For the user-facing
> version, see §6.5 of the
> [prototype usage guide](../usage/01_prototype_usage_guide.md). The methodology
> this implements is the project's conceptual specification; this document
> describes what was built, how to read it, and — at least as prominently — what
> it does not claim.

## 1. What the workflow is for

VAWLUME's correspondence layer relates detections produced by independent
extractors. This workflow characterizes those relationships for one dataset. It
answers four questions:

1. what does the candidate-correspondence space look like here;
2. how sensitive are the inferred extractor relationships to plausible matching
   thresholds;
3. what kinds of detections belong to each exact extractor-support pattern;
4. what do representative examples of those patterns look like in raw
   spectrographic context.

It is an exploration, not a calibration. It selects no threshold, recommends
none, ranks no configuration, and produces no composite score.

### 1.1 Confidence-relevant support is not the same as detection-strategy convergence

This is the conceptual heart of the workflow and the thing a reader is most
likely to flatten, so it is stated before anything else.

When several extractors report the same event, that can mean two different
things:

- **Confidence-relevant evidence.** A call detected independently by several
  systems may be more likely to reflect a robust acoustic event.
- **Detection-strategy convergence.** Agreement also identifies the calls that
  are *simultaneously amenable to the detection strategies of the participating
  extractors*. A multiply detected call may simply belong to an easy or
  stereotyped population.

These overlap and are not identical, and nothing in the output distinguishes
them — because nothing in the data can. Every summary the workflow produces is
compatible with both readings.

The evidential relationship is also **asymmetric**. Several independent
detections may raise confidence; one extractor failing to report an event does
**not** establish that the event is false. An extractor-unique detection is a
support pattern, not an error category.

## 2. The stages

`vawlume.eda.runExploration` sequences the workflow. It orchestrates: every
stage is a call to the function that owns that calculation, and the orchestrator
defines no metric, estimates no effect and computes no summary of its own.

| Stage | What it does | Functions |
|---|---|---|
| `dataset` | Resolve and validate recordings, runs and extractor pairs before anything executes | `resolveDataset` |
| `reference` | Apply the tracked reference configuration to every recording | `referenceConfiguration`, `referenceDesign`, `materializeConfigurations`, `runScreen` |
| `diagnostics` | Distributions, Pearson, Spearman, partial correlation, coverage, redundancy | `candidateMetrics`, `metricDistributions`, `metricDependencies` |
| `probe` | Decide which threshold dimensions to screen and at what values | `explorationOptions`, `probeParameters` |
| `screen` | A bounded, interaction-aware design over the whole dataset, and its responses and effects | `screeningDesign`, `probeCost`, `materializeConfigurations`, `runScreen`, `screenResponses`, `mainEffects`, `leverageCategories` |
| `subset` | A seeded, stratified recording sample and a richer probe over it | `resolveStrata`, `sampleRecordings`, `subsetDesign`, `runScreen`, `screenResponses`, `mainEffects`, `leverageCategories` |
| `concordance` | Compare the two probes, per factor per response | `probeConcordance` |
| `support_patterns` | Characterize exact extractor-support patterns at the reference | `supportPatternProfile`, `crossPatternComparison` |
| `examples` | Sample and render a representative spectrogram gallery | `sampleExamples`, `exportExampleGallery` |
| `exports` | Tables, figures, example index, provenance | `plot*`, `render*`, `writeTableExport` |

### 2.1 Why the reference configuration runs first

The development plan sketches diagnostics as stage one. In the implementation
they cannot be: the diagnostic battery reads **stored candidate pairs**, and
probe values are anchored on quantiles of those same observed metrics. Both
require that some matching analysis has already been applied to this dataset.

Applying the tracked reference configuration first supplies them, and it is the
same run the support-pattern characterization and the gallery are computed at,
so nothing is executed twice. A caller who already holds matching analyses can
point the diagnostics at them with `DiagnosticAnalyses`.

### 2.2 Running one stage

Stages are individually runnable. `Stages="diagnostics"` runs the dataset,
reference and diagnostic stages and stops — no design is built and no probe is
executed. Prerequisites are included automatically, because refusing instead
would make "run only the diagnostics" something nobody can do.

Every stage a run did not perform appears in `result.stages` with its reason, so
a partial result cannot be mistaken for a complete one. `status` is `completed`
when every *requested* stage completed; a stage nobody asked for is recorded as
`not_requested` rather than as a skip.

`Apply=false` plans every design and reports its cost. **No analysis, no export
and no provenance record is written**; the generated matching specifications
still are, under the output root, because they are what the reported cost is a
cost of. The export stage skips:
writing a plan's tables would put files where the real run's exports belong, and
the real run would then refuse to overwrite them, so a dry run would break the
run it was meant to price.

A dry run over a database nothing has matched yet prices the reference run and
stops, because probe values are anchored on observed candidate-pair
distributions and there are none. Naming an existing analysis source with
`DiagnosticAnalyses` — `struct(project_key="…")` is enough once the reference
configuration has been applied once — lets the diagnostics, the probe values and
both designs be planned and priced without writing anything.

## 3. The analysis-cost arithmetic

**Read this before running a probe over a real dataset.** For `C`
configurations, `R` recordings and `N` extractors:

```
matching   = C × R × N(N−1)/2
agreement  = C × R
total      = C × R × (N(N−1)/2 + 1)
```

For three extractors that is `4 × C × R`. A configuration count therefore
understates the real work roughly fourfold, and that factor is what turns a
design that looked like a small screen into an overnight run.

Two independent ceilings apply, and they bound different things:

| Ceiling | On | Warn | Refuse without explicit opt-in |
|---|---|---|---|
| Design, whole-dataset screen | configurations | 32 | 128 |
| Design, subset probe | configurations | 64 | 256 |
| Execution, either probe | **analyses** | 250 | 2 500 |

The configuration ceilings bound the design, which cannot see the dataset. The
analysis ceiling bounds the work, and it is the one that binds in practice. When
it binds it is because the dataset turned out larger than the design assumed;
the remedy belongs to the caller — fewer recordings, a smaller configuration
budget, or `AllowExceedingMaximum` — and the refusal names all three rather than
truncating the probe to fit.

`probeCost` reports the estimate before each probe executes, and
`runExploration` prints it. The light configuration's `analysis_budget` field,
when set, **overrides the analysis ceiling** — it binds the work rather than the
size of the design, because that is what a user asking for a budget means. The
value in force and where it came from are recorded in
`result.analysis_budget` and in the provenance record.

**When the budget binds, reduce the fraction, never the factor set.** Dropping a
factor silently removes a dimension the user asked about; accepting more
aliasing at least discloses the cost.

## 4. The diagnostic battery

`candidateMetrics` assembles one row per stored candidate pair — temporal IoU,
overlap, signed and absolute onset/offset/duration differences, candidate score,
and one feature-discrepancy column per eligible equivalence class. It defines no
metric: temporal values are read from `candidate_pairs` and feature
discrepancies come from `vawlume.consilience.summarize`.

Two conventions the result states rather than assumes:

- Pairs are ordered by **ascending `extractor_key`**, and every signed
  difference is higher key minus lower key. `candidate_pairs` orders its two
  detection columns by detection id to satisfy a schema CHECK, so neither the
  stored columns nor the schema can supply direction; it is resolved through
  `analysis_run_extraction_inputs.input_role` and cross-checked against each
  row's `details_json`. Without that, pooled signed differences would be bimodal
  for a reason that is not biological.
- `extractor_key_a`/`_b` and `detection_a_id`/`_b_id` use **different orderings
  and are not aligned**. `lower_extractor_detection_id` and
  `higher_extractor_detection_id` state the mapping so no consumer has to infer
  it.

### 4.1 Coverage is five categories, not one

Every metric reports counts in five disjoint categories that sum to the row
count:

| Category | Meaning |
|---|---|
| `supported` | present and finite |
| `not_eligible` | the feature pair is not registered as comparable for those extractors |
| `not_measured` | eligible, but one extractor did not measure it for that detection |
| `not_comparable_topology` | the pair's match group is not `one_to_one`, so the specification never attempted the comparison |
| `non_finite` | present but NaN, Inf, or SQL NULL |

These are five different facts about a dataset, and collapsing them into one
"missing" count destroys the distinction needed to decide what is computable.
`non_finite` is not hypothetical: `temporal_iou` is explicitly NaN for two
coincident zero-duration intervals, because 0/0 has no overlap fraction.

### 4.2 Correlations, and what an undefined partial correlation means

Pearson and Spearman are reported side by side, every cell carrying its
observation count. The matching metrics are bounded and skewed — `temporal_iou`
lives in [0, 1] with a hard edge at its own gate — so Pearson measures something
real but easily misread, and Spearman is the robust companion. Reporting one
invites a reader to treat it as *the* dependency.

Partial correlation is computed from the precision matrix,
`partial(i,j) = −P(i,j) / sqrt(P(i,i)·P(j,j))`, with four guards applied
**before** inversion rather than as exception handling around it: constant
column, near-constant column, insufficient complete observations, and
ill-conditioning.

The insufficiency floor is complete-case `n < p + 10`, where `p` is the number
of retained metrics. It is a deliberate additive margin for real analyses: with
four metrics, fewer than 14 complete observations leaves partial correlation
undefined. Small demonstration or pilot datasets may therefore produce an
entirely undefined partial matrix even when the implementation is working as
designed. Pearson and Spearman then use the labelled pairwise fallback; the
partial matrix stays undefined rather than being made finite by regularization.

**There is no ridge or shrinkage regularization, by default or otherwise.**
Regularizing converts a singular matrix into a finite, plausible-looking number,
which is precisely the failure this layer exists to avoid.

An undefined cell is `NaN` **plus a reason** from a fixed vocabulary:

```
constant_column        near_constant_column       insufficient_observations
ill_conditioned        no_overlapping_observations
```

The reason is first-class output, not a log line. A reader seeing an undefined
partial correlation needs to know whether the metric was constant in this
dataset or whether the matrix was too ill-conditioned to invert; those imply
different next steps. **An undefined value is a finding, not a gap.**

Missing values follow a two-stage policy, and `observation_policy.mode` records
which ran, because the two give different matrices and the numbers alone do not
say which. Primary is listwise deletion over the retained metrics — one sample
for every cell, which the partial correlation requires. When the complete-case
count falls below the floor, Pearson and Spearman are computed **pairwise and
labelled pairwise**, and the partial matrix is reported entirely undefined. The
fallback is expected rather than hypothetical: feature-discrepancy columns are
sparse wherever an extractor registers few comparable features.

### 4.3 Redundancy is reported, never pruned

A strongly correlated pair of metrics is recorded as a redundancy finding and
carried into the probe resolution and the leverage report. **No dimension is
deleted on the strength of a correlation statistic**, and no factor is ever
deactivated for being redundant. The finding travels so the leverage report can
be read in its light; the factor is screened anyway.

Everything is implemented in base MATLAB — Pearson through `corrcoef`, Spearman
through a mid-rank helper, partial through `inv` and `rcond`, quantiles through
`vawlume.eda.sampleQuantile`. `corr` and `partialcorr` are Statistics and
Machine Learning Toolbox functions in every release; `quantile`, `prctile` and
`iqr` are base MATLAB in R2026a but were not always, so the helpers stay for
release portability.

## 5. The whole-dataset screen

### 5.1 Which factors, and at what values

Four matching dimensions may be screened:

```
min_temporal_iou                max_abs_onset_difference_s
max_abs_offset_difference_s     max_abs_duration_difference_s
```

The three `max_abs_*` bounds are optional, and **absent means unconstrained**.
The `max_abs_` prefix is contractual: it makes the signed-versus-magnitude
question unanswerable by guessing.

Probe values come from two sources, in priority order: an explicit user override
for that factor, otherwise quantiles of the observed metric —
q(0.10)/q(0.50) of `temporal_iou` for `min_temporal_iou`, and q(0.50)/q(0.95) of
the corresponding absolute difference for each `max_abs_*` bound.

Quantile anchoring rather than fixed constants, because a hard-coded pair can
sit entirely outside a dataset's observed range and produce a factor that
reports zero leverage for a reason that has nothing to do with the science.

**"Low" and "high" name the parameter value, not the strictness.** A larger
`min_temporal_iou` is stricter; a larger `max_abs_*` bound is looser. Each
factor records its `strictness_direction`, and without it the sign of a main
effect is uninterpretable.

`max_abs_duration_difference_s` is an **absolute-seconds, scale-dependent
axis**, not a duration ratio. On a dataset spanning 10 ms to 200 ms calls, a
0.02 s bound is a 200% tolerance on the short calls and a 10% tolerance on the
long calls, while the screen reports one leverage number for the factor. Read
that leverage as sensitivity to one absolute bound over this population, not as
a uniform relative-duration tolerance. A shared scale-free duration definition
remains deferred until `vawlume.interval.relation` is deliberately extended.

A factor is reported **inactive with its reason** — `disabled_by_user`,
`metric_absent`, `insufficient_coverage`, `degenerate_interval` — rather than
screened at an arbitrary value. An invariant design column destroys the design's
balance and yields a main effect of exactly zero that looks like a finding.

The resolution also reports whether each probed interval **brackets the
reference configuration's value**. It frequently does not, and that is worth
knowing: it means the screen explores a neighbouring region rather than the
neighbourhood of the configuration the extractor-set characterization uses.

### 5.2 The design, and the aliasing warning

The design is a full `2^k` factorial when it fits the configuration budget, and
otherwise the largest fitting fraction: the full factorial in the first `k − p`
factors as a ±1 matrix, with each remaining factor defined as the element-wise
product of a stated subset — its **generator**. Generator choice is
deterministic for a given `(k, p)`, from a documented lookup rather than a
search, because otherwise `configuration_id` values would not line up between
the two probes and concordance would be impossible.

**A fractional design cannot separate every effect, and the output says so.**
Design metadata carries `generators`, the `defining_relation`, the `resolution`,
and an `alias_table` covering every main effect and every two-factor
interaction, with what each is confounded with.

- At **resolution IV**, main effects are clear of two-factor interactions and
  two-factor interactions are aliased in pairs, so an interaction estimate is
  the *sum* of its aliased pair rather than either member.
- At **resolution III**, every main effect is confounded with a two-factor
  interaction. A resolution-III screen therefore makes **no leverage claim about
  any factor**: the leverage layer categorises every otherwise-informative pair
  as `interaction_suspected`, from the design alone, whatever the estimates look
  like.

That is not the screen failing. It is the screen declining to make a claim its
design cannot support, and it is exactly what the alias trigger exists to
produce. A screen reporting a clean large main effect without disclosing its
confounding is worse than no screen, because it is read with more confidence
than it has earned.

There is no randomized run order and no blocking: the computation is
deterministic, so there is no experimental noise to randomize against.

### 5.3 Responses and effects

Response families, per configuration and per recording, plus a pooled scope:
detections considered, pairwise match counts, agreement-group counts, **exact**
extractor-support-pattern counts, extractor-unique counts and fractions,
ambiguous-group counts, and cross-configuration change measures (`retained`,
`lost`, `gained`, `split`, `merged`, `reconfigured`).

Counts pool by summation. **Fractions are always recomputed from pooled counts,
never averaged across per-recording fractions** — the two differ, and the
difference grows with unequal recording lengths.

A main effect is the difference of response means between a factor's high-level
and low-level runs, **in the response's own units**, reported beside that
response's range across the design.

There is deliberately **no normalized effect size aggregated across responses**.
That is a composite score under another name. There are also **no p-values,
confidence intervals or significance tests**: the design has no replication and
this MVP makes no distributional claim.

An **incomplete design is refused by default**. Effect estimates assume every
design row was evaluated on the same recordings; where a unit failed, the
difference of means is taken over unequal sets and the number is not the
quantity it claims to be. `OnIncompleteDesign="label"` computes anyway and marks
every row, for a caller who has read the completeness report.

### 5.4 Leverage categories

Five categories, evaluated top to bottom, first match wins:

| Category | Rule |
|---|---|
| `insufficient_information` | the response range is zero or non-finite, the estimate is not finite, too few supported runs, or the factor was inactive |
| `interaction_suspected` | the design aliases main effects, **or** the strongest interaction involving the factor is nonzero and at least 0.50 × \|effect\| |
| `high_leverage` | \|effect\| / range ≥ 0.50 |
| `moderate_leverage` | 0.20 ≤ \|effect\| / range < 0.50 |
| `low_leverage` | \|effect\| / range < 0.20 |

`insufficient_information` outranks everything for a reason: a response constant
across the entire design yields a zero main effect for every factor, and
categorising that as `low_leverage` would report every factor as inert. That is
the highest-consequence misclassification available here.

**The cut points are a reporting convention, not an inferential threshold.** The
output says so.

## 6. The subset probe and the comparison

### 6.1 Sampling

The subset is where the extra search budget is spent; the full dataset gets the
compact screen.

Strata are **recording-level only**. The admitted grammar is
`recording_attribute:<name>`, `entity_attribute:<name>`, `epoch:<type>`, and
`recording`. `support_pattern` and `extractor_set` are refused by name, because
support pattern is an *output* of the correspondence analysis the subset exists
to probe; stratifying on it would condition the sample on the thing being
measured.

A field qualifies automatically when, over the dataset's recordings, it resolves
to a non-missing value for at least 60%, has at least two distinct non-missing
values, has no single stratum holding more than 90%, and produces fewer strata
than recordings. Every field considered is recorded with why it was accepted or
rejected — the decision is automatic, so it must be inspectable. If none
qualifies, the sample falls back to seeded random and **says so** rather than
producing a "stratified" sample with one stratum.

Four rules that earn their place:

- **Missing resolves to the literal stratum `"(missing)"`** and is never
  dropped. It appears in summaries and is eligible for sampling.
- **A multi-valued field raises** when the caller named it. A recording can have
  two genotypes, and choosing one silently is how a stratified sample becomes
  wrong. During automatic discovery such a field is rejected with its reason
  instead, so one unusable candidate does not destroy the usable ones.
- **Resolution never goes through `v_recording_entity_context`**, whose inner
  joins make a recording with no entity link vanish entirely.
- **An under-full stratum is reported short with its actual count** — never
  padded from a neighbour, never dropped. A stratified sample whose strata are
  secretly unequal is worse than an honestly unbalanced one, because the reader
  interprets it as balanced.

Size defaults to `max(4, min(12, ceil(0.25 × R)))` recordings, clamped to `R`,
and is configured as a count rather than derived from an analysis budget — a
budget-derived size would change whenever the design changed, making two runs
incomparable for a reason the user never chose. Sampling uses a local
`RandStream` over a frame ordered by ascending `native_recording_id`; `rng`
would mutate global MATLAB state, so the draw would stop being a function of its
inputs.

**Size the subset probe against `realized_size`, not `requested_size`.** They
differ whenever a stratum is under-full or the one-per-stratum floor raises the
total.

An explicit request larger than the resolved frame returns the whole frame and
sets `requested_exceeds_frame = true`; `OnExcessRequest="raise"` selects strict
failure instead. The caller cannot know the resolved frame size before strata
are resolved, so the default preserves the completed resolution work and makes
the difference visible.

### 6.2 Concordance

The two probes cover the same factors — a differing factor set is refused
outright, because a short comparison table reads as agreement — and both are
two-level, so their effect estimates are the same quantity.

Both probes also share one exploration run key. A configuration present in both
designs is the *same point in parameter space*, so its analyses are found and
reused rather than recomputed; where the probes overlap they agree exactly, and
any divergence is attributable to design and dataset rather than to two
executions of one computation drifting apart.

The comparison is a **table, one row per factor per response identity**: leverage
category on each side, whether they agree, direction where both are
interpretable, the effects and ranges, and a `reading` sentence. A response
observed by one probe and not the other gets a row with
`presence = "screen_only"` or `"subset_only"` and the category `not_observed` on
the absent side — never a dropped row.

**There is no concordance score, no agreement fraction, and no ranking**, and
none may be derived downstream: an "agreement rate" computed from the
contingency counts would reintroduce the composite through the figure layer.

Disagreement is reported as informative, not as error. The probes differ in both
design and dataset, so divergence may mean the compact screen is misleading, or
that the subset is unrepresentative, or that an effect genuinely varies across
recordings. The output names those possibilities and adjudicates between none.

A common and benign pattern: most divergence is `interaction_suspected` on the
screen against a magnitude category on the subset probe. That is not the probes
disagreeing about the data. It is a fractional screen declining to make a claim
and a full factorial being able to make one.

**Probe agreement does not establish that manual calibration is unnecessary.**
The probes share every assumption of the matching and agreement layers, so they
cannot detect an error common to both, and neither observes ground truth at any
point. That sentence always travels in `calibration_note`, table provenance and
the concordance figure. Its substance appears in a row's `reading` only when
the probes agree on both category and interpretable direction; category
agreement with withheld direction does not claim directional agreement.

## 7. Exact support patterns

### 7.1 Two vocabularies that must never be joined

"Support pattern" names two different things in this repository, and they cannot
be joined:

| Vocabulary | Key | What it is |
|---|---|---|
| **Extractor set** | `extractor_set_key` | Which extractors contributed to the group. For three extractors this is the seven categories: each extractor alone, each pair, and the triple |
| **Supported pair pattern** | `supported_extractor_pair_pattern` | Which extractor *pairs* actually corroborated each other |

`supportPatternProfile.patterns` keys on the **extractor set**, because that is
what the seven categories are. Every singleton group's pair pattern is `(none)`
whichever extractor produced it, so keying on the pair pattern would merge the
three extractor-unique categories into one — the exact collapse the methodology
forbids, arriving through a column whose name says "support pattern".

The profile reports `pair_patterns` beside `patterns`, labelled, and never joins
them. The screening responses and the threshold ranges carried from the probe
are keyed on the **pair** pattern; the example index's column 9 is the pair
pattern too, while the gallery's rows are drawn per extractor set. Label every
figure with which one it shows.

A generic `k of C(N,2)` count may accompany the exact pattern. It never replaces
it: two groups can both support two of three pairs while supporting *different*
pairs.

### 7.2 Reading the profile

Characterization is done at one clearly named **reference configuration** — the
tracked default at
`config/05_matching_profiles/prototype_matching_consilience_spec.json` unless
the caller supplies another. It is **never chosen from the screen's results**:
selecting the configuration that maximizes three-way support and then describing
three-way support would be circular, and the resolver is given no access to a
design, a probe result or a leverage table so the circularity is unreachable
rather than merely forbidden.

Using that file as a reference **does not calibrate it**, and running a
sensitivity probe around it does not either. Its own `calibration_status` block
declares `illustrative_prototype` and states that every numeric threshold is a
deterministic demonstration value. That status is carried verbatim into every
output that names the configuration.

Every pattern gets a row, **including zero-count ones**: an absent row and a
zero row look the same in a table and mean different things.

The agreement layer is **recording-scoped**, so a reference run over `R`
recordings produces `R` agreement analyses and one profile each.
`runExploration` profiles every one and reports them separately under
`support_patterns.profiles`, with `primary` — the profile with the most groups —
used for the figures and named there. **They are not pooled**, because pooling
them would be a calculation no function owns. A pooled multi-recording profiler
does not exist in this MVP.

Permitted reading:

> Within this dataset, detections in one support pattern differed in their
> duration distribution from those in another. The denominators and coverage
> beside each summary are part of that statement, not decoration.

Not permitted: that an extractor is inherently specialized for a call type, that
a support class carries more confidence, or that any numeric weight follows from
support count.

## 8. Shared features, and why the space is thin

**Comparability is registered, never inferred.** Feature pairs are discovered
through `extractor_features.equivalence_class` and `feature_relationships` with
`consilience_eligible`, exposed by `v_cross_extractor_feature_pairs`. Sharing an
equivalence class does not imply comparability, and the pilot registry contains
the trap: DeepSqueak's "Peak Freq (kHz)" and USVSEG's "maxfreq" share the class
`vocalization_peak_frequency` and are **not** registered as comparable, so no
peak-frequency summary is produced for that pair. An implementation that grouped
by equivalence class would have produced one.

Transitivity is not assumed either: a class is comparable among a set of
extractors only when *every* pair in that set has a registered relationship.

Across the three pilot extractors the registered shared space is **two features
wide**:

| Class | Scope |
|---|---|
| `vocalization_duration` | comparable across all three — usable on a cross-pattern axis |
| `vocalization_frequency_center` | comparable across all three — usable on a cross-pattern axis |
| `vocalization_frequency_min` / `_max` / `_bandwidth` | registered for DeepSqueak–MUPET only — reportable *within* `deepsqueak`, `mupet` and `deepsqueak + mupet`, never across patterns |
| `vocalization_peak_frequency` | registered by DeepSqueak and by USVSEG; no relationship pairs them, so it is usable nowhere |
| `vocalization_frequency_cv` | USVSEG only |

That thinness is a **methodological limitation of the extractor set and its
registry**, reported rather than closed by speculative harmonization. No feature
relationship was registered to widen it.

### 8.1 Feature availability is confounded with support pattern

A pattern's members come from specific extractors *by definition*. Bandwidth
exists for a DeepSqueak–MUPET group and cannot exist for any pattern containing
USVSEG. A bandwidth-by-pattern plot would compare populations that differ in
whether the measurement exists at all, and the apparent difference would be the
extractor composition rather than the calls — while the plot looked entirely
reasonable.

`vawlume.eda.crossPatternComparison` therefore **refuses** an
extractor-restricted feature rather than returning it with a flag. A flag is
something a caller reads when they remember to; a refusal at the point of use
cannot be skipped by not noticing. The refusal names the patterns the feature
*is* reportable in.

Duration is admissible here even though the matching specification reserves it
as primary temporal evidence. That reservation exists so temporal evidence is
not double-counted when *classifying* correspondence; describing what kinds of
detections occupy a pattern is a different question. Start and end time stay
excluded on their own merits — a start time is a position in a recording, not a
property of a call.

### 8.2 Coverage

Coverage — contributing detections over pattern population — is reported beside
**every** feature summary, per feature per pattern, in the same five categories
as §4.1. A duration distribution computed from 9 detections and one computed
from 4 000 look identical in a figure.

Below 0.50 a row is marked `low_coverage` and **reported anyway**: a
low-coverage feature is itself a finding about the extractor set, not a row to
drop. A pattern with no members at all is labelled `no_population` and is
explicitly not marked low-coverage — zero over zero is not a small fraction.

## 9. The spectrogram gallery

Three examples per exact support pattern by default (configurable 1–10), drawn
with a local `RandStream` over a deterministically ordered frame at the
reference configuration. A pattern with fewer members than the target yields all
of them plus a **reported shortfall**; it is never padded from a neighbouring
pattern, because a gallery with three images per row where one row borrowed from
another misrepresents exactly what the gallery exists to show.

This is a gallery, **not a review pool**. There is no verdict column, no notes
column and no re-import path.

### 9.1 Overlay semantics — what is drawn and what never is

The spectrogram is computed from the **original audio** with base MATLAB `fft`
and an inline periodic Hann window, never from an extractor-rendered image.
Every annotation is drawn from measurements the extractor actually supplied:

| `frequency_extent_source` | Meaning | Rendering |
|---|---|---|
| `band_edges` | both minimum and maximum registered and measured | rectangle |
| `center_only` | centre frequency only | time extent + one horizontal marker |
| `peak_only` | peak frequency only | time extent + one horizontal marker |
| `center_and_peak` | both, no band edges | time extent + two markers |
| `unavailable` | no frequency measurement | time extent only |

A time extent spans the full displayed frequency axis in a visibly distinct line
style, so it cannot be mistaken for a measured rectangle, and the legend states
which extractors contributed measured band edges and which did not.

**No band is ever synthesized** from a centre value, a peak value, a coefficient
of variation, a fixed offset, or assumed call geometry.

### 9.2 The USVSEG frequency-extent limitation

**USVSEG contributes no measured frequency band edges.** Its export carries
`maxfreq`, `meanfreq` and `cvfreq`; it does not carry a minimum, and a band
reconstructed from a centre plus a coefficient of variation would be an
invention presented at the same visual weight as a measurement.

USVSEG annotations therefore show a **time extent plus measured markers**, and
any group containing a USVSEG detection shows a mixture: rectangles for
DeepSqueak and MUPET, full-height boundary lines and markers for USVSEG. That
mixture is the honest picture, and the legend says so in words
(`usvseg — no measured band; center_and_peak`).

Rectangles for DeepSqueak and MUPET are **summary-value extents, not native
contours**. The MVP renders what the ingested data represent.

### 9.3 The example index

A fixed 22-column, comma-delimited, UTF-8 CSV (`example_index.csv`), written
beside `example_index_caution.txt` and an `images/` directory. Multi-valued
columns use `|` and are member-aligned, so a reader can zip
`member_detection_ids`, `member_extractor_keys`, `member_native_event_ids` and
`frequency_extent_sources`.

A failed example **keeps its row** with `render_status = "failed"` and its
reason: an omitted row looks like an example that was never sampled, which
misrepresents the pattern's coverage.

The canonical caution travels in the adjacent sidecar rather than as a 23rd
column, because the column set is fixed and a review-like addition is forbidden.

## 10. Outputs and provenance

`runExploration` writes, under `<OutputRoot>/exploration/<run key>/`:

```
specs/      one generated matching specification per configuration
gallery/    example_index.csv, example_index_caution.txt, images/*.png
exports/
  tables/   one CSV per computed table, each with a provenance header line
  figures/  one PNG per figure family
  exploration_provenance.json
```

Every exported CSV begins with one line,
`# vawlume_table_export=<JSON>`, carrying the run identity and the canonical
caution. Consumers that only need the table read it with `NumHeaderLines=1`.

`exploration_provenance.json` records what the linked analyses and the
registered design record do not already imply: the resolved seed and its
derivation basis, every factor with its interval, quantile and value source, the
design type, generators, defining relation, resolution and configuration
identities for both probes, the predicted analysis cost, the subset's
stratification field and realized membership, the example seed and gallery
counts, and the reference configuration's identity and calibration status.

**There is no selected-threshold field**, and there is not going to be one.
Creating one would invite exactly the reading the methodology forbids.

Figure export refuses degenerate inputs by design — a metric with one finite
value, a screen with one configuration, a feature with no eligible extractor
set. On thin data those refusals are the honest answer, so the run records which
figures were not drawn rather than abandoning the set.

The coverage table is drawn with ordinary axes graphics and exports through the
same exact-size path as every other figure. Main-effect figures carry a factor
key stating which value is stricter. Dependency figures use a larger 16×14-inch
default; above eight metrics, undefined cells remain crossed while their reason
vocabulary moves to the figure note instead of repeating unreadable prose in
every cell. Interpretation notes and the canonical caution occupy independent
regions, so long optional prose cannot displace the caution.

Persistence: the matching and agreement analyses are applied normally,
append-only and checksum-bearing; one `analysis_runs` row of type
`consilience_exploration` links the probes, with each probe distinguishable by
its `ProbeRole`. Diagnostics, responses, effects, concordance and profiles stay
**transient** and are exported as files, because they are exactly recomputable
from the stored analyses and persisting them would create a second source of
truth that can go stale. **No schema change was required or made.**

## 11. The example workflow script and the template

- [`examples/consilience_exploration_demo.m`](../../examples/consilience_exploration_demo.m)
  builds a disposable six-recording synthetic project and runs the whole path
  over the real public functions. It is asserted by
  [`tests/integration/test_consilience_exploration_demonstration.m`](../../tests/integration/test_consilience_exploration_demonstration.m),
  including that two independent runs make identical automatic choices. It
  deliberately shows thin data: a resolution-III screen that makes no leverage
  claim, three empty extractor sets, and six extractor sets that cannot supply
  the requested number of examples.
- [`examples/templates/consilience_exploration_workflow_template.m`](../../examples/templates/consilience_exploration_workflow_template.m)
  is the ten-section template to copy and edit. Everything configurable is in
  section 1; the rest calls public functions and reads their results. It lives
  in a subdirectory because everything directly under `examples/` is a shipped
  demonstration covered by an integration test, and the template is neither.

## 12. Limitations

Read this section as a section. Each item is something a reader could otherwise
infer wrongly from an output that looks authoritative.

1. **Agreement is not ground truth.** Extractors can share biases, and a
   detection reported by only one extractor may still be a real vocalization.
2. **Non-agreement is not symmetric evidence of illegitimacy.** One extractor
   failing to report an event does not, by itself, establish that the event is
   false. No output may describe three-way support as universally superior or an
   extractor-unique detection as invalid.
3. **No threshold is recommended, selected, or calibrated.** The reference
   configuration is a reference; its own status is `illustrative_prototype`.
   Adding screenable dimensions and running a sensitivity probe around a value
   does not calibrate that value.
4. **Probe agreement does not remove the need for calibration.** Both probes
   share every assumption of the matching and agreement layers and neither
   observes ground truth.
5. **A fractional design aliases effects it cannot separate**, and a
   resolution-III screen can make no leverage claim about any factor at all. The
   alias table is part of the result, not a footnote to it.
6. **The shared feature space is thin.** Only duration and centre frequency are
   comparable across all three pilot extractors; everything else is
   extractor-restricted and confined to the patterns where every contributing
   extractor registers it.
7. **USVSEG contributes no measured frequency band edges**, so its annotations
   show a time extent and measured markers only. No band is synthesized from a
   centre, a peak, a coefficient of variation, or assumed geometry.
8. **The support-pattern profile is per recording.** Agreement is
   recording-scoped and no pooled profiler exists; the profiles are reported
   separately and must not be summed without deciding what a pooled denominator
   would mean.
9. **The cut points are a reporting convention.** No p-value, confidence
   interval or significance test is computed anywhere, and the design has no
   replication.
10. **Every empirical statement is about one dataset.** Nothing here generalizes
    to an extractor's behaviour in general.

## 13. Explicit non-goals

The following were described in the conceptual specification as deferred and
are **not implemented**. None of them exists in the code, so a reader should not
go looking.

- **Human-in-the-loop review.** No review pool, review manifest, annotation
  vocabulary, manual label, or review re-import. The gallery is illustrative.
- **Threshold optimization or recommendation.** No objective function, no argmax
  over configurations, no automatic selection.
- **Any composite score** — no stability score, no concordance score, no
  probe-agreement score.
- **A full downstream robustness battery.** Biological or experimental group
  analyses are not rerun across unions, pairwise intersections, three-way
  intersections or weighted support schemes.
- **A weighted confidence model.** No numeric weight is assigned from support
  count.
- **Peri-call or song-context profiling** — no local call density, no
  rapid-succession structure, no neighbouring-call sequences.
- **Large whole-dataset Cartesian grids.** Not the default and not supported by
  the budgets.
- **Advanced search** — no Bayesian optimization, active learning, adaptive
  search or surrogate models.
- **A GUI, app, or interactive review surface.**
- **Exact extractor-native contour reconstruction.** The overlays use measured
  extents and markers already represented in the ingested data.
- **Multi-level designs.** Both probes are two-level, so their effect estimates
  are the same quantity. Adding levels is a contract change, not a parameter.

## 14. Tests

| Suite | What it holds to account |
|---|---|
| `tests/integration/test_consilience_exploration_demonstration.m` | The whole workflow end to end, its costs and design sizes, determinism across two independent runs, stage skipping, repository hygiene, and the template |
| `tests/integration/test_eda_candidate_metric_surface.m` | Direction resolution, the five coverage categories, the package-wide write scan |
| `tests/unit/test_eda_metric_distributions.m`, `test_eda_sample_quantile.m` | Distribution summaries and the base-MATLAB quantile definition |
| `tests/unit/test_eda_metric_dependencies.m` | Pearson, Spearman, partial correlation, guards, the pairwise fallback |
| `tests/unit/test_eda_probe_parameters.m` | The configuration surface, probe-value resolution, inactive reasons, anti-pruning |
| `tests/unit/test_eda_screening_design.m` | Design construction, budgets, generators and the alias table |
| `tests/integration/test_eda_exploration_runner.m`, `test_eda_generated_specifications.m` | Execution, run keys, reuse, byte-exact specification serialization |
| `tests/integration/test_eda_screen_responses.m`, `tests/unit/test_eda_screen_effects.m` | Response families, pooling, effect estimates and incomplete designs |
| `tests/integration/test_eda_stratum_resolution.m`, `tests/unit/test_eda_subset_sampling.m` | The stratum grammar, qualification, allocation and the local random stream |
| `tests/integration/test_eda_subset_probe.m`, `tests/unit/test_eda_leverage_concordance.m` | The second probe, leverage categories and the concordance table |
| `tests/integration/test_eda_support_pattern_profile.m`, `tests/unit/test_eda_support_pattern_rules.m` | Registry-only comparability, coverage, and the cross-pattern refusal |
| `tests/unit/test_eda_spectrogram_core.m`, `test_eda_example_rendering.m`, `tests/integration/test_eda_example_sampling.m`, `test_eda_example_gallery.m` | Snippet windows, overlay geometry, no synthesized bands, the fixed index |
| `tests/unit/test_eda_visualization_layer.m` | Figure families, preserved unknowns, exports |
