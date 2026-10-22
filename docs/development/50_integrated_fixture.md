# 50. The integrated fixture

`vawlume.db.buildIntegratedFixture` builds one synthetic dyadic session that
carries everything a cross-path or cross-event-set comparison needs. It
returns an open connection and a manifest of every identifier a consumer
needs. Built at itinerary 7.3, with the imported and backend scenes added at
7.3a. Contract 07 D11 is the design.

**Status: internal.** The builder is public only so that the Phase 7 tests and
the Phase 7 demonstration can call one builder. It is not user API.

```matlab
[fixture, cleanup] = vawlume.db.buildIntegratedFixture();          % under tempdir
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(Root=folder, RepoRoot=repoRoot);
fixture.conn            % open connection to the fixture database
fixture.manifest        % every id a consumer needs; see below
clear cleanup           % closes the connection and removes every file it wrote
```

`Root` must not exist yet, or must be empty. `RepoRoot` defaults to the
repository holding the builder.

## Every row through a public function

The builder writes no SQL of its own. Each step is a call a user could make:

| Step | Through |
|---|---|
| Two recordings of one dyad (animals A and B): `session`, two channels; `secondmic`, one channel | `vawlume.source_mapping.parse`, `vawlume.ingest.project` |
| DeepSqueak, MUPET and USVSEG imports of `session`; USVSEG of `secondmic` | `vawlume.ingest.deepsqueak` / `mupet` / `usvseg` |
| Three pairwise matching analyses under the tracked specification; one arbitrary-N agreement; their consensus events | `vawlume.matching.compare`, `vawlume.agreement.compose` |
| Audio clock: affine from three anchors, about 200 ppm drift. Tracking (video) clock: piecewise affine with a declared breakpoint | `vawlume.ingest.alignment`, `vawlume.alignment.fit` — **one alignment set per method** |
| A declared frame, two placed channels, tracking in that frame, time-valid identity associations including a swap | `vawlume.geometry.*`, `vawlume.tracking.*` |
| A noise family **and** a tone family in the call band, measured on both channels, one response estimate run | `vawlume.acoustic.registerReference`, `measureReferenceResponse`, `estimateChannelResponse` |
| Per call: a call-window measurement and a band-matched normalization | `measureCallWindow`, `normalizeCallLevels` |
| Native runs over DeepSqueak detections and over DeepSqueak–MUPET consensus events; an imported run and a backend run over the same detections; each decided | `vawlume.estimator.attributeCallers`, `vawlume.ingest.attribution`, `vawlume.ingest.backendAttribution`, `vawlume.attribution.correspondWindows` / `addCandidates` / `decide` |

The alignment rows show the **public alternative** to the Phase 6 tests'
workaround. A manifest's `method` applies to its whole alignment set, so a set
cannot mix affine and piecewise transforms. Here each method has its own set.
`vawlume.db.buildAlignmentSessionFixture`, which several module tests share,
still switches its audio run to piecewise by a direct `UPDATE` before fitting.
Its help text documents that workaround.

## The scenes

In audio-native seconds. Each is one call unless stated.

| Scene | Time | What it is |
|---|---|---|
| `separable` | 30.0 | A near microphone a, B on the bisector |
| `unfittable` | 31.2 | 8 dB louder at b, which neither position predicts |
| `model_mismatch` | 31.5 | A's prediction minus 10 dB of unmodelled directivity |
| `coverage_gap` | 60.0 | Identity clear, no tracking sample |
| `symmetric` | 70.0 | Both animals on the bisector |
| `identity_swap` | 110.0 | The two tracks swap identities mid-call |
| `split` | 140.0 | MUPET reports one DeepSqueak call as two (a `one_to_many` unit) |
| `merge` | 145.0 | DeepSqueak reports one USVSEG call as two (a `many_to_one` unit) |
| `miss` | 150.0 | MUPET reports nothing (an extractor-specific miss) |
| `out_of_bracket` | 160.0 | Tracking samples beyond the tracking clock's anchors (`bracket_extrapolated = true`, contract 07 D20) |

**The second microphone** stands for a real rig's separately started file. The
native path refuses it with `vawlume:estimator:InputRecordingMismatch`, which
is why native attribution is not applicable to the real Pilot 3 recordings
(contract 07 D12).

**Real-shape tokens:** MUPET's terminal `_` interval, a USVSEG `NaN` feature,
and a DeepSqueak zero-height box. Each is stored raw with no numeric payload.

**For the CSV audit:** the project description carries a non-ASCII character
and an embedded newline.

## The manifest

`fixture.manifest` names every id, so no consumer hard-codes one:

| Field | Holds |
|---|---|
| `project_key`, `recording_id`, `second_microphone_recording_id` | The project and both recordings |
| `entities` | Animals A and B |
| `extraction_runs` | The four extraction runs |
| `scenes` | One row per scene: its times; its DeepSqueak, MUPET and USVSEG detection ids; its consensus event; its target id in each attribution run; how it was built. Also the imported and backend scores the builder wrote |
| `correspondence` | The matching and agreement analyses |
| `real_shape_tokens` | Where each token sits |
| `alignment`, `tracking`, `acoustic` | Alignment runs and sets; the tracking stream and frame; the response run, references and normalization policy |
| `runs`, `profiles` | The attribution runs and the profile versions they cite |
| `artifacts` | Every file the build wrote |
| `csv_values` | The audit values, with a note |
| `boundary` | The circularity statement below |

## Everything is synthetic and circular

The imported and backend claims are claims this builder wrote. The separable
and symmetric calls follow the native method's own spreading assumption.
**Agreement between paths on this fixture shows that the machinery joins
correctly, never that any path is accurate.** `manifest.boundary` repeats this,
and every Phase 7 document that reports a result on the fixture says so.

## Who uses it

- `tests/integration/test_integrated_fixture.m` asserts the scenes, tokens and
  manifest.
- The Phase 7 comparison, sensitivity and QC-fact tests
  (`test_attribution_compare*.m`, `test_attribution_sensitivity.m`,
  `test_correspondence_sensitivity.m`, `test_qc_facts.m`), the localization
  evidence test, and the integration checks (`test_integration_checks.m`).
- Module tests that need moving trajectories or the piecewise audio clock use
  `buildAlignmentSessionFixture` instead (contract 07 D11, corrected at 7.3a).

## Not here

- No real data. The real Pilot 3 acceptance runs are in the development
  repository's harness, not in this builder.
- No persistence. The database is disposable, and `cleanup` removes it.
- No claim about any method's accuracy (above).
