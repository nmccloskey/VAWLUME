# 51. Integrated validation demonstration

`examples/integrated_validation_demo.m` carries the shared Phase 7 fixture
(doc 50) through every Phase 7 public function in one runnable script:

- three attribution paths compared on one recording;
- runs over different event sets compared through named stored analyses;
- declared inputs varied in two sensitivity families;
- the native QC facts read;
- the database exported and read back strictly.

It composes public functions and computes nothing itself. Built at itinerary
7.16. Contract 07 is the design; the 7.1 settlements it follows are named
below.

**Status: experimental** (usage guide, "Status of public functions"), like the
functions it exercises.

```matlab
addpath("src"); addpath("examples")
demonstration = integrated_validation_demo();             % prints the read-backs
demonstration = integrated_validation_demo(Print=false);  % returns them only
```

It runs in about two minutes on a development workstation, most of it spent
building the fixture. Every file is created under `tempdir` and removed before
return; `demonstration.temporary_artifacts_removed` says so.
`tests/integration/test_integrated_validation_demonstration.m` asserts it.

## What the workflow covers

| Section | Public functions | What is printed | Guard (7.13 table) |
|---|---|---|---|
| The scene | `buildIntegratedFixture`, `attribution.report` | Each extraction run's detections; each path's run with its table row counts beside what one row of each table is | — |
| Cross-path comparison | `attribution.compare` | Per pair, the one-to-one units by cell kind and the score comparability. The separable call's unit row against its status cross-tab. The symmetric call's structural empty, and the same pair as a disagreement against backend. The imported run's declared inputs, all `unknown` | E1, E2, R1 |
| Cross-event-set comparison | `attribution.createRun` / `addCandidates` / `decide`, then `compare` with `Correspondence=` | The split (`one_to_many`), merge (`many_to_one`) and miss (`unmatched_left`) units, with the splitting side named, each side's status, and the named analysis and join kind. Unit counts per extractor pair and against consensus events | E3 |
| Attribution-side sensitivity | `ingest.alignment` + `alignment.fit` (the offset refit), `eda.attributionSensitivity`, `eda.sensitivitySummary` | The dry run writing nothing. One variant per handle. The six handles not varied, as rows with their reasons. The generated tone normalization. The alignment variant citing the offset fit, with its out-of-bracket call carrying `bracket_extrapolated=true` | E4, E8 |
| Upstream sensitivity | `eda.correspondenceSensitivity`, `eda.sensitivitySummary` | The dry run writing nothing. The temporal variant losing targets; the spectral variant moving no event set; `matching_duration` reported `not_variable` | E5 |
| QC facts | `estimator.qcFacts` | The separable, symmetric, unfittable (out of range) and model-mismatch calls, with the undetectable-class statement every row carries | E6 |
| Refusals | as below | Five refusals, each with its identifier | E15 and the compare suites |
| Export | `export.database` | The manifest's mode, schema, object and row counts; a strict read of five tables against SQLite; the non-ASCII, multi-line value surviving | E12 |
| Closing | — | Native rows unchanged, zero foreign-key violations, artifacts removed, `proves` / `does_not_prove` | E8 |

**The 7.1 settlements it follows:**

- Units print in contract 07 D3's oriented vocabulary (`one_to_many`,
  `many_to_one`), with the splitting side named.
- The tone-family alternative is generated at runtime (D6). No `config/` file
  is added.
- Real-data results are cited from 7.14a/7.14b, not re-run.

## The runs over every event

The fixture's own runs target only its seven attribution scenes. For the
cross-event-set section, the demonstration writes four `native_estimate` runs:
over every DeepSqueak, MUPET and USVSEG detection, and over every
DeepSqueak–MUPET consensus event. They go through `createRun`, `addCandidates`
and `decide` with **synthetic scores**, exactly as
`test_attribution_compare_correspondence` does. Those scores mean nothing; the
runs exist to exercise the stored join. The output says so.

## Refusals

A harness fails the example if a refusal stops refusing, **or if it refuses
under a different identifier**. The Phase 6 ledger recorded a harness that
checked failure but not identifier, which is why the identifier is now checked
too.

| Attempted | Identifier |
|---|---|
| A score comparison across paths (imported against native) | `vawlume:attribution:ScoreNotComparable` |
| A native-score comparison across settings-profile versions (the reference against the `estimator_settings` variant) | `vawlume:attribution:ScoreNotComparable` |
| A comparison across event sets with no named analysis | `vawlume:attribution:CorrespondenceAnalysisRequired` |
| A hand-written probability on a native candidate (invariant 24) | `vawlume:attribution:NativeProbabilityRefused` |
| A label-only pose row on a native candidate (invariant 26) | `vawlume:attribution:NativeIdentityCitationRequired` |

The first run of the demonstration met a sixth refusal it had not planned
for. After the decision-policy variant, the reference native run carries two
decision sets, and `compare` refused to guess between them
(`DecisionPolicyRequired`) before it reached the score check. The probes now
name the reference policy (`LeftPolicy=` / `RightPolicy=`). That is the harness
working: an identifier other than the expected one fails the example.

## Boundaries the example does not cross

- No combination outside `+estimator/`.
- No ranking of paths, variants or settings.
- No probability.
- No calibrated threshold.
- No re-matching to make a join.
- No value compared across a scale boundary.
- No real data.

## What the demonstration could not show

These are the places a sweep should look first.

- **A disagreement between paths that the generator did not author.** Every
  disagreement shown (the separable call, the symmetric call against backend,
  the decision-policy variant's status change) was constructed by the fixture
  builder or the declared variant. Nothing here shows the comparison finding
  something nobody put there.
- **Any real-data comparison.** The real Pilot 3 recordings have one channel and
  no tracking, so no native run exists on them, and the protocol-derived imported
  claims (R2-H) were not run. `compare` has never read a real attribution run.
- **The model-mismatch class.** The QC facts state the 6.15 dB tolerance and the
  3.85 dB margin of the model-mismatch call, and every fact looks ordinary. The
  demonstration can only say that; it cannot show a signal that does not exist.
- **A `many_to_many` unit.** The fixture has none. Its handling is covered by
  `test_attribution_compare_correspondence`'s stored-component test, not shown
  here.
- **Scores side by side (`CompareScores=true`) where they are comparable.** The
  printed pairs are all `not_comparable`, or the variant summary's
  `scores_changed`. `test_attribution_compare` covers the comparable case.
- **A sensitivity variant applied part-way and re-applied.** The partial-apply
  behaviour (variants applied, no family record) is documented in doc 47, not
  shown.
- **Sensitivity on real data, and its cost.** Both orchestrators run here on the
  fixture only (roughly 8–18 s per matching-side configuration); no real-data
  run of either was made in v2.
- **An unscored state beyond the fixture's** (coverage gap, identity swap, out of
  bracket): the reasons are in the compare output but not printed one by one
  here. `test_attribution_compare` asserts them.
- **The schema-only export and `validateMetadata(Mode="complete")`.** E12's
  companion test covers them; the demonstration exports only the normal package.

## Validation limitation

Everything is synthetic and circular. One builder wrote every path's input, so
agreement between paths shows that the machinery joins correctly, never that
any path is accurate. Real-data acceptance (7.14–7.14b) used four
right-microphone recordings with no tracking, geometry or ground truth for who
called; it cannot bear on cross-path agreement.

## See also

- Doc 46 (comparison), 47 (sensitivity), 48 (QC facts), 50 (the fixture).
- The usage guide §7.10.
- Contract 07.
