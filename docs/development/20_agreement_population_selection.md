# Agreement population selection and EDA hooks

Phase 1.10 adds a read-only MATLAB entry point over the Phase 1.9 agreement
views:

```matlab
population = vawlume.agreement.selectPopulation(conn, analysisRef, ...
    Name=Value)
```

It selects analysis-ready agreement groups without introducing a generic
confidence score. The returned observations are still the native detections in
`agreement_group_members`; the agreement group remains a derived connected
component and is never converted into consensus timing.

## Analysis reference

`analysisRef` must resolve exactly one completed
`multi_extractor_agreement` run. Supported forms are:

```matlab
struct(analysis_run_id=17)
struct(run_key="agreement-v1")
struct(project_key="project-a", run_key="agreement-v1")
```

Adding `project_key` disambiguates a run key reused across projects. A pending,
failed, or wrong-type analysis is rejected with a named error rather than
silently returning an empty population.

## Independent filters

| Option | Meaning |
|---|---|
| `ExactSupportPattern` | Exact stable extractor-pair pattern |
| `MinSupportedPairCount` | At least K supported extractor pairs |
| `ExactSupportedPairCount` | Exactly K supported extractor pairs |
| `ExactPossiblePairCount` | Exact `N*(N-1)/2` denominator |
| `Completeness` | `any`, `complete`, or `incomplete` pair support |
| `Cleanliness` | `any`, `clean`, or `not_clean` source topology |
| `Multiplicity` | `any`, `one_per_extractor`, or `multiple_per_extractor` |
| `Uniqueness` | `any`, `extractor_unique`, or `corroborated` |
| `ExtractorSetKey` | Exact represented extractor set |
| `RecordingId` | Optional recording scope |
| `EntityId` | Optional recording-linked entity scope |

Every supplied option is combined with `AND`. Exact shape and coarse strength
are deliberately separate. Two groups may both be 2 of 3 while supporting
different pairs; `ExactSupportedPairCount=2` includes both, whereas
`ExactSupportPattern` selects only the requested shape.

Examples:

```matlab
% All three possible pairs among these three extractors.
allThree = vawlume.agreement.selectPopulation(conn, ref, ...
    ExactSupportPattern="deepsqueak--mupet|deepsqueak--usvseg|mupet--usvseg");

% DeepSqueak--MUPET and DeepSqueak--USVSEG, but not MUPET--USVSEG.
exactShape = vawlume.agreement.selectPopulation(conn, ref, ...
    ExactSupportPattern="deepsqueak--mupet|deepsqueak--usvseg", ...
    ExactSupportedPairCount=2, ExactPossiblePairCount=3);

% A coarse population that intentionally admits every exact shape at K >= 2.
coarse = vawlume.agreement.selectPopulation(conn, ref, ...
    MinSupportedPairCount=2);

% Complete, clean, one-detection-per-extractor triples.
cleanComplete = vawlume.agreement.selectPopulation(conn, ref, ...
    ExtractorSetKey="deepsqueak|mupet|usvseg", ...
    Completeness="complete", Cleanliness="clean", ...
    Multiplicity="one_per_extractor");

% Complete pair support with within-extractor multiplicity retained.
completeAmbiguous = vawlume.agreement.selectPopulation(conn, ref, ...
    Completeness="complete", Cleanliness="not_clean", ...
    Multiplicity="multiple_per_extractor");

uniqueCalls = vawlume.agreement.selectPopulation(conn, ref, ...
    Uniqueness="extractor_unique");
```

`MinSupportedPairCount` and `ExactSupportedPairCount` may be combined only when
the exact value satisfies the minimum. Singleton `support_fraction` is returned
as MATLAB `NaN`, corresponding to SQL `NULL`; it is not changed to zero.

## Result and identity contract

The result contains:

- `analysis` and `filters`, the resolved scope and normalized request;
- `groups`, one row per selected `v_agreement_group_summary` row;
- `members`, every matching `v_agreement_group_members` row;
- stable `agreement_group_ids` and native `detection_ids` vectors;
- explicit selected group and member counts.

A split/merge component therefore remains one group with all of its native
members. Callers can summarize group counts, member counts, or extractor-level
measurements, but must state which denominator they use.

`EntityId` means that the recording is linked to that entity. It is context
scope, not caller attribution. For time-varying context, join member onsets to
`v_recording_entity_context.start_time_s/end_time_s` explicitly. Feature joins
should use `detection_id` against `v_event_measurements_long`, retaining
`agreement_group_id` and `group_key` in the result.

## Synthetic EDA demonstration

[`agreement_filter_demo.m`](../../examples/agreement_filter_demo.m) creates a
disposable fixture and shows:

- all groups, at-least-two-pair, exact all-pair, and exact open-chain filters;
- clean complete triples, complete ambiguous components, and extractor-unique
  calls as separate populations;
- native members joined to two synthetic time-bounded condition windows through
  `v_recording_entity_context`;
- descriptive group/member counts by window and call-duration summaries by
  window and extractor through `v_event_measurements_long`.

The windows and calls are synthetic. The example performs no hypothesis test,
model fitting, plotting, threshold calibration, caller assignment, or claim of
biological validity.

## Tests

`tests/integration/test_agreement_population_selection.m` proves selection,
read-only behavior, named invalid-request errors, independent completeness,
cleanliness and multiplicity filters, and—critically—separation of two exact
2-of-3 pair patterns with the same coarse count.

`tests/integration/test_agreement_filter_demonstration.m` verifies the runnable
context/measurement example, preserved group/member identity, expected
condition summaries, cleanup, and foreign-key integrity.
