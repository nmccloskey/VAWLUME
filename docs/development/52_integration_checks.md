# 52. Integration checks and what they would not catch

Plan §12 names six checks that the integrated system must pass. Contract 07
D13 added the closure guards that hold Phase 7 to its own rules. This document
maps each one to the tests that guard it, and records what each guard **would
not catch**.

- **Origin:** itinerary 7.13 wrote the map. 7.17 re-verified every guard by
  injection on the live tree.
- **Why it is recorded here:** a guard's blind spot is part of its contract.

## How a guard is known to work

Every guard below was **injection-verified**: a scratch copy of the tree
received the violation the guard exists to catch, and the guard's test had to
fail.

- **7.13** injected 38 violations. **7.17** repeated all 38 against commit
  `e0c4d8a` and added five: **43 of 43 fired**.
- The harnesses and per-injection logs live in the development repository, not
  here: `08_phase7/04_gate_runs/p713_injection/` and `p717_injection/`.
- **The exception, C3** (the storage check that native evidence cites its
  alignment run), cannot be reached by a production-code violation. An
  injection is refused one layer earlier, by the evidence writer
  (`vawlume:attribution:EvidenceSourceRequired`). The storage check is a second
  layer behind the writer, not a guard that has been seen to fire.

## Plan §12's six checks

| Check | Guards (test file / test) | Would not catch |
| --- | --- | --- |
| **1. Provenance-preserving source mapping** | The three extractor export-adapter suites and `test_table_field_mapping`; `test_integrated_fixture/testTheRealShapeTokensSurviveAsRawTokens`; **E7** `test_integration_checks/testRealShapeTokensTraceToTheTargetsTheyReach` | A token on a path no fixture run takes. USVSEG `NaN` is traced only as far as agreement |
| 1, paths | **E16** `test_resolve_path`; invariant 54 `test_package_boundaries/testTheJavaFileIdiomAppearsOnlyInItsHome` | A path resolved by a non-Java route outside `vawlume.internal.resolvePath`. Invariant 54 scans `src/` only |
| **2. Native data never overwritten** | **E8** `test_integration_checks/testNativeTablesAreUnchangedByThePipeline` (compare, report, qcFacts, export, exploration), and E8 in `test_attribution_sensitivity` and `test_correspondence_sensitivity` | A write to a table outside the 16 native tables; a pipeline step these suites do not run |
| **3. One transform representation** | **E9** `test_localization_evidence/testNoTransformArithmeticOutsideTheAlignmentPackage`; the alignment transform suites; C3 `test_integration_checks/testEveryStoredTransformHasOneRepresentation` | Coefficient arithmetic on renamed variables (E9 is a scanner). C3 is unreachable by a code violation (above) |
| **4. No needless dense duplication** | **E10** `test_integration_checks/testDoublingTheDenseInputsChangesNoRowCount` (duration and frame rate doubled) | Duplication that scales with something other than duration or frame rate |
| **5. One canonical result structure** | Invariant 16 `test_native_estimation_run/testAllThreePathsReadBackThroughOneFieldSet`; **R1** `test_attribution_compare/testEveryPathPairHasTheSameOutputShape`; E1–E3 below | A field identical in name but different in meaning across paths |
| **6. No semantic coupling** | **E11** `test_package_boundaries/testSharedPrimitivesAndAttributionDependOnlyWhereAllowed` (invariant 53); `testMatchingPackageIsUntouched`; `testNothingOutsideTheEdaPackageNeededEditing` | Coupling through data (a domain flag in a shared table) rather than code |

## Phase 7's own guards

| Rule | Guard | Would not catch |
| --- | --- | --- |
| Comparison is not combination | **E1** `test_attribution_compare/testTheOutputIsAClosedVocabularyAndCombinesNothing` (a closed output vocabulary and banned words) | Combination under a neutral output name |
| A structural empty is not a disagreement | **E2** `test_attribution_compare/testSimultaneousAgainstANativeStatusIsAStructuralEmpty`; `test_policy_rule_declarations` (every decision rule declares its producible statuses) | A status vocabulary change outside the decision rules |
| Correspondence comes from storage | **E3** `test_attribution_compare_correspondence/testSplitMergeAndMissAreTheManifestsUnits`; `testTheJoinIsReadOnlyAndCallsNoMatchingOrIntervalCode` (a static scan of `compare` and its two join helpers) | Interval arithmetic or a planner call in a helper the scan does not list |
| Sensitivity selects nothing | **E4** `test_attribution_sensitivity/testTheSummarySelectsNothing` (forbidden words; rows ordered by handle, never by outcome) | A ranking expressed only in prose outside the summary |
| A spectral variant moves no event set | **E5** `test_correspondence_sensitivity/testASpectralVariantLeavesEveryEventSetIdentical` | — |
| QC facts write nothing | **E6** `test_qc_facts/testNothingIsWrittenOrChanged` | — |
| The CSV export is faithful | **E12** `test_integration_checks/testTheIntegratedDatabaseExportsFaithfully`; `testTheSchemaOnlyExportAndTheMetadataAreComplete` | Fidelity of non-attribution tables beyond headers and counts |
| The exploration fabricates no extent | **E13** `test_integration_checks/testTheExplorationDiagnosticsRunWithoutAFabricatedExtent` | Fabrication in stages beyond diagnostics |
| Registry sync appends | **E14** `test_seed_registration/testSyncingADatabaseSeededWithAnOlderVersionAppendsTheShippedOne` | A sync that rewrites feature mappings but not versions |
| Invariants 24 and 26 at storage | **E15** `test_integrated_validation_schema` (each trigger); `test_canonical_write_enforcement` (each API refusal, and each trigger as the last line of defence) | — |
| A demonstrated refusal keeps refusing, with its identifier | `test_integrated_validation_demonstration/testEveryRefusalRefusedWithItsIdentifier`; the demonstration's own harness | A refusal the demonstration does not attempt |

## Phase 6's guards, re-verified

Phase 6's twelve guards were re-injected by 7.13 and again by 7.17. All fire.

- Spatial arithmetic only in `+geometry` (invariant 19).
- Combination only in `+estimator` (invariant 5).
- No track label compared with an entity identifier (invariant 26).
- The estimator writes no SQL (invariant 30), and reads no imported or backend
  row (invariant 25).
- The native policy never says `simultaneous` (invariant 27).
- Every native score is reconstructible from storage (invariant 23).
- One field set (invariant 16).
- The native demonstration's refusals.
- The three settings refusals of 6.12a.

**Accepted blind spots** (contract 07, inherited-ledger audit):

- hand-written arithmetic;
- combination under a neutral name;
- invariant 26 on one line;
- text after `%` inside a string, for the invariant-25/30 scanners.

## What this document is not

It is not a gate. A guard firing under injection shows that the guard can
fail. It does not show that the rule holds in code the guard does not reach,
which is what each "would not catch" entry is for.
