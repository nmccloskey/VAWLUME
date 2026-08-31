# Common-time views and regularized timeline

## Scope

This checkpoint reads vocalization and external events on one selected reference
clock and constructs a small MATLAB-native binned timeline. It follows stored
transform fitting and QC; it does not refit clocks, change native evidence, or
implement sequence analytics.

```matlab
view = vawlume.alignment.commonTime(conn, alignmentRef, ...
    VocalizationSource="detections", VocalizationRunId=runId)
result = vawlume.sequence.regularizeTimeline(view, channels, ...
    WindowStart=t0, WindowEnd=t1, BinWidth=width, BinOrigin=origin)
```

[`examples/temporal_alignment_demo.m`](../../examples/temporal_alignment_demo.m)
is a disposable synthetic audio/video/neural demonstration of the whole path.

## Vocabulary and authority

A **timebase** is a clock coordinate system. A **stream** is a logical source of
events observed on a timebase and may have several source files. The alignment
set chooses one timebase as its **reference** for a particular analysis; that
choice does not make the device intrinsically more accurate.

A **logical anchor** identifies one coordinating occurrence such as a sync
pulse. Its **observations** are the native readings of that occurrence on
different clocks. A session manifest identifies the concrete files, clocks,
streams, profiles, and reference choice; a reusable mapping profile states how
one kind of source table is interpreted. They are different provenance objects.

Offset and affine transforms use:

```text
reference_time = scale * source_time + offset_s
```

Per-anchor residuals are the observed reference reading minus the prediction.
They make the fit inspectable; they are not a calibrated acceptance decision.

The scientific authority remains:

```text
native timestamp + source timebase + alignment set + stored transform
```

Aligned timestamps are derived. `commonTime` reads `alignment_segments` through
`applyTransform`, never refits, and never updates detections, consensus events,
external events, coverage, or anchor observations. Events already on the
reference timebase retain their values and say `alignment_kind="identity"` with
no invented transform run. Other events say `stored_transform` and carry the run
that produced their coordinates.

`aligned_external_events` is an optional regenerable cache for relational reads
and exports. `commonTime` does not require or populate it. There is no
`aligned_detections` authority.

## Common-time event contract

The derived event table is a union, not a coercion into `external_events`. It
keeps calls as detections or consensus events and carries source kind and event
identity; recording, stream, source and reference timebase identities; native
and aligned intervals; normalized and native labels; alignment identity;
coverage key; and provenance.

The caller deliberately selects `detections` or `consensus_events` and names the
corresponding extraction or analysis run. Consensus is never substituted for an
unmatched or ambiguous detection merely to fill a timeline.

## Coverage

External coverage intervals are projected through the same stored transform as
their events. Vocalization coverage comes from `0 -> recordings.duration_s` when
duration is known. Unknown duration creates no fictional observed interval.

Every event and interval carries a `coverage_key`. An external event outside its
declared coverage raises `vawlume:alignment:EventOutsideCoverage` by default; a
caller may request a warning for audit workflows. Events never extend coverage.

The regularizer considers a bin covered only when one observed interval contains
the complete bin. This conservative rule prevents a partially observed bin or a
gap between segments from becoming an observed zero.

## Regularization semantics

Requests resolve reference timebase, window, bin width, bin origin, channels,
aggregation, coverage, and edge convention. Window bounds must lie on the grid
and contain a whole number of bins. Every bin is half-open `[start,end)`: an
onset exactly on an interior edge belongs to the bin beginning at that edge, and
the final `WindowEnd` is excluded.

Supported prototype aggregations are `onset_count`, `presence`, and
`any_overlap`. Each requested channel returns both `<name>` and
`<name>_covered`:

```text
> 0  event present
0    covered and no matching event (absent)
NaN  not covered / unavailable
```

The explicit coverage column prevents missing-value conversion from turning an
unavailable bin into a scientific zero.

## Storage and phase boundary

The timeline is a derived MATLAB table. No dense empty bins are written to
SQLite, and `sequences` / `sequence_members` remain untouched. Phase 7 provides
the aligned, regularized foundation only. Transition matrices, entropy, n-grams,
motifs, edit distance, bouts, hierarchy analysis, continuous neural samples, and
automatic interpretation remain out of scope for the later sequence phase.

The synthetic demo proves that known transforms can be recovered, stored QC can
be read back, native and aligned event coordinates can coexist, identity is
explicit, and covered-empty differs from unavailable. It does not prove real
device accuracy, establish calibrated residual thresholds, or claim complete
video/neural synchronization.
