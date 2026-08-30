# Consilience, manual QC, and threshold sensitivity

## Public API

```matlab
report = vawlume.consilience.summarize(conn, analysisRef)
report = vawlume.consilience.summarize(conn, analysisRef, Apply=true)
report = vawlume.consilience.sensitivity(conn, analysisRefs)
```

`summarize` adds a consilience status per match group and an evaluation against
an independent manual reference to the agreement report. `sensitivity` compares
several already-applied matching configurations side by side and is read-only.

## Consilience statuses

### Vocabulary and rules

One automated status per match group, assigned by a frozen rule set carried in
the versioned specification:

| Status | Rule |
|---|---|
| `single_extractor` | `match_type = unmatched` |
| `ambiguous_split_merge` | `one_to_many`, `many_to_one`, or `many_to_many` |
| `matched_feature_discrepant` | `one_to_one` with at least one eligible supporting comparison outside its declared tolerance |
| `matched_feature_supported` | `one_to_one` with at least `minimum_supporting_comparisons` eligible comparisons inside tolerance |
| `temporally_matched` | `one_to_one` with fewer supporting comparisons available than the configured minimum |

`manually_reviewed`, `adjudicated_positive`, and `adjudicated_negative` belong to
the manual sub-vocabulary and are never written into
`consilience_assessments.status`. See precedence below.

### What each status does and does not mean

`single_extractor` means exactly one thing: **no eligible cross-extractor
correspondence survived this matching specification**. It is not a false
positive, not an invalid call, and not a statement about biological confidence.
The rule text stored on every such assessment says so, and the report's
`terminology_note` repeats it.

The fixture makes the point concretely: single-extractor groups in it are split
between reference-supported and reference-absent. If the status implied
falsehood, that split could not exist.

### Precedence

```text
manual adjudication
  > ambiguous topology
  > temporal correspondence plus feature evidence
  > temporal correspondence
  > single extractor
```

Ambiguous topology deliberately outranks feature evidence: averaging the two
MUPET syllables of a split component to compare against one DeepSqueak call would
need an aggregation model that does not exist, so an ambiguous component can
never earn a feature-supported status.

**Manual adjudication never overwrites the automated status.** What persists in
`consilience_assessments.status` is the automated status; the manual verdict
lives in its own `manual_reviews` row joined by match group; and the
precedence-resolved `effective_status` is computed for the reader and never
stored. A query for `status` therefore always returns what the algorithm decided,
and no value beginning `adjudicated` ever appears in that column.

### Status is not probability

`consilience_assessments.score` is left **NULL**. A consilience status is a
categorical evidence summary under one versioned rule set, and no calibration
exists that would justify storing a number as a probability that a vocalization
occurred. The specification must declare `consilience.score_is_probability:
false`, and each assessment's `rationale_json` records why the score is omitted.

### Evidence behind each status

`rationale_json` on every assessment carries the rule set (profile key, version,
checksum, algorithm key and version), the matching analysis, the topology, the
automated status and the rule text that produced it, the feature evidence
(available, within, outside, not computed, which equivalence classes were
discrepant, the configured minimum, the missing-feature policy, and that
ineligible relationships were excluded), the temporal evidence read from the
candidate row, and the manual verdict with its review id.

### Missing versus discrepant

A supporting comparison that could not be computed **neither supports nor
contradicts**. It only reduces the count of available support, so a group with
one usable comparison and three missing ones falls back to `temporally_matched`
rather than being called discrepant. The specification declares this as
`missing_feature_policy: not_a_discrepancy` and the loader refuses any other
value, because treating an unexported measurement as disagreement would
manufacture a discrepancy from a missing column.

### Ineligible relationships

Power, energy, and amplitude are registered as `related` with
`consilience_eligible = 0`. Driving those measurements arbitrarily far apart
changes no status, no supporting count, and no comparison — asserted by test.
Only eligible pairs with a declared tolerance count as supporting evidence, and
the timing classes reserved as primary temporal evidence are excluded so one
piece of evidence is never counted twice.

## Manual QC anchor

### The schema gap this pass closed

`manual_reviews` adjudicates something that already exists: a detection, a match
group, or a consensus event. It therefore could not represent an event that no
extractor found, which made recall and false negatives unrepresentable. Phase 6
Pass 1 recorded that as schema pain and specified the smallest correction.

This pass adds one table:

```sql
manual_reference_events(recording_id, reference_set_key, native_reference_id,
                        reviewer_label, start_time_s, end_time_s,
                        event_status, reviewed_at_utc, notes)
```

Reviewer-authored events, scoped to the **recording and a named reference set,
not to an analysis run**, so one reviewed subset anchors every configuration
compared against it. Nothing else changed: `manual_reviews` keeps its existing
role, and the two layers stay separate.

### Independence

A manual label is never derived from extractor state. `curation_events`,
native class labels, and detector scores are excluded by the specification and
absent from the classifier and from reference construction — asserted statically.
An extractor evaluated against its own accept flag would agree with itself.

The fixture makes the independence visible in both directions: a DeepSqueak call
the extractor accepted that the reviewer did not mark, and a call the extractor
rejected that the reviewer did.

### Coverage and what it gates

Whether a reference set annotates the whole recording is a property of how it was
produced, so it is declared in the versioned specification rather than assumed by
the schema:

```json
"coverage": "exhaustive_over_recording"   // or "partial"
```

Precision needs no such claim. **Recall and the false-negative count are withheld
under `partial` coverage** — reported as NaN and omitted from persistence
entirely — because a detection with no overlapping reference event might simply
lie in a region nobody reviewed.

### Detection-to-reference matching

Deliberately **separate from the extractor-to-extractor rule**, so neither can be
tuned through the other:

```text
require positive overlap, temporal IoU >= manual_qc.matching_rule.min_temporal_iou
greatest-IoU assignment, each reference event and each detection used at most once
```

The one-to-one assignment matters: without it, both syllables of a split
component could claim the same reference event and inflate true positives.

### Metrics

Per run: detection count, reference event count, true positives, false
positives, false negatives, precision, recall, and mean absolute onset and offset
error over the linked pairs. Every unmatched reference event is reported per run
rather than silently dropped.

### Contingency and the poster question

The automated status is cross-tabulated against independent evidence: per status,
the group count, how many groups contain a reference-supported detection, how
many do not, and how many were adjudicated positive or negative.

This is **counts only**. It is not a calibrated predictive claim, and the
prototype question — whether cross-extractor consilience targets manual review
differently from relying on one extractor alone — is one this table can only
illustrate on a synthetic fixture.

### DeepSqueak `Accepted`

Reported as a secondary cross-reference: per extractor and curation state, how
many detections are reference-supported and how many are not. It generates no
manual label and enters no status rule, and the specification declares both
facts. MUPET contributes no curation rows at all, so the table is DeepSqueak-only
by construction rather than by filtering.

## Threshold sensitivity

### Configurations

Each configuration is a separate specification file with its own profile key,
version label, and checksum, applied through `vawlume.matching.compare` as its
own analysis. Sensitivity reads them back; it creates nothing.

The shipped specification declares three:

```text
strict        min_temporal_iou = 0.50
illustrative  min_temporal_iou = 0.10
permissive    min_temporal_iou = 0.05
```

One parameter varies. Input runs, algorithm version, assignment model, consensus
policy, feature eligibility and tolerances, and the manual reference set are all
held constant, and `sensitivity` **refuses** to build a table whose analyses
differ in recording, run pair, algorithm version, or reference set — otherwise
the differences in the table would not be attributable to the threshold.

### What the fixture shows

| Configuration | IoU | Candidates | 1:1 | 1:N | Unmatched groups |
|---|---:|---:|---:|---:|---:|
| permissive | 0.05 | 5 | 3 | 1 | 2 |
| illustrative | 0.10 | 4 | 2 | 1 | 3 |
| strict | 0.50 | 2 | 2 | 0 | 5 |

Loosening admits a weak-overlap pair the default leaves apart; tightening
dissolves the split component into unmatched detections.

Manual precision and recall do **not** move across the three rows, because they
are computed against the reference under the separate manual rule. That
invariance is a consequence of keeping the two rules apart, and it is asserted by
test.

### No optimization

**No configuration is selected as best.** The report carries a caution stating
that the table shows how outcomes move with an uncalibrated threshold, that none
of these values is optimal, validated, or calibrated, and that choosing the one
with the best synthetic manual agreement would be fitting a threshold to a
fixture. Calibration requires real paired extractor output and real independent
annotation.

## Persistence

### What is stored

Consilience assessments and aggregate statistics commit **in one transaction**
under the child `cross_extractor_agreement` analysis run. One assessment per
match group, targeting the group, with the automated status, the rationale, and a
NULL score.

Manual evaluation is persisted as `detection_agreement` statistics namespaced
`manual.<run_role>.…` so no reader can confuse agreement between the two
extractors with agreement against a reviewer, plus
`manual.contingency.<status>.…` diagnostics. Every row's notes carry the
reference set key, the coverage declaration, the manual matching threshold, and
the caution.

### Atomicity

A failure while writing assessments rolls back the statistics too, leaves no
`cross_extractor_agreement` analysis row at all, restores autocommit, and leaves
the matching analysis it summarizes untouched. A database can never claim a
completed agreement analysis while only some groups carry a status.

### Rerun and change

A rerun with identical statistics **and identical statuses** reuses the existing
child and writes nothing. Any difference raises
`vawlume:consilience:AgreementConflict`. Nothing is updated in place: a corrupted
stored status makes the next apply conflict rather than being silently repaired.

Changed thresholds produce a new matching analysis and therefore a new agreement
child; an earlier result is never rewritten.

## Terminology

Used deliberately: cross-extractor consilience, agreement, supporting evidence,
manual adjudication, prototype threshold, reference-supported.

Avoided, and absent from the source except as explicit negations: ground truth,
verified true call, confidence probability, optimal threshold, validated
performance.

## Limitations

- the reference subset is synthetic and small; it demonstrates evaluation logic
  and is not scientific performance evidence;
- precision and recall are computed against one reviewer-authored set under one
  declared matching rule, both of which are configuration;
- recall is unavailable under partial coverage, by design;
- no aggregation model exists for ambiguous components, so they receive no
  feature-based status;
- the manual reference matching rule is itself an uncalibrated threshold;
- no configuration in the sensitivity table is calibrated, and none should be
  described as optimal;
- every extractor artifact remains synthetic, so every number here demonstrates
  computation rather than measuring extractor performance.
