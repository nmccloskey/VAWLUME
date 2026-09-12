# Channel-response estimates and QC profiles

Phase 2.7 aggregates exact Phase 2.6 response measurements into reproducible,
uncalibrated channel-response evidence. One
`acoustic_channel_response_estimate` analysis run is the response/QC profile;
its children are `channel_response_estimates`. The table deliberately uses
"estimate", not "profile", because `config_profiles` remains reserved for
authored versioned configuration.

This layer does not normalize calls, choose a channel, calculate caller scores,
or claim an empirically calibrated hardware response.

## Aggregation boundary

`vawlume.acoustic.estimateChannelResponse` accepts an explicit vector of
`derived_measurement_id` values. Every ID must resolve to a real-valued,
canonical-unit measurement of an acoustic reference on a declared channel and
must come from an `acoustic_reference_response` run for the selected recording.
The exact selection avoids a query whose population could silently change.

```matlab
preview = vawlume.acoustic.estimateChannelResponse(conn, recordingRef, ids, ...
    RequiredReferenceTypes=["tone", "noise"], ...
    MinReferences=2, DivergenceRelativeThreshold=0.25);

stored = vawlume.acoustic.estimateChannelResponse(conn, recordingRef, ids, ...
    RequiredReferenceTypes=["tone", "noise"], ...
    MinReferences=2, DivergenceRelativeThreshold=0.25, ...
    SettingsProfileVersionId=policyVersionId, ...
    Apply=true, RunKey="session01-response-profile");
```

The initial aggregation method is deliberately one method: median, version
`1.0.0`. Rows remain separate by recording channel, metric definition,
`reference_type`, and exact optional frequency band. Each row also records the
mean, standard deviation, minimum, maximum, relative range, measurement count,
and distinct reference count in `details_json`. This provides interpretable
stability evidence without pretending a single opaque gain is justified.

An optional `analysis_settings` profile version may be linked to the owning run
with role `response_aggregation_policy`. The JSON details also preserve its key,
version, URI, and checksum. The built-in method version and all scalar policy
arguments are recorded even when no external settings profile is used.
The explicit API arguments are the executed settings; the optional profile link
records the authored policy provenance and does not silently override them.

## Divergence and QC policy

`DivergenceRelativeThreshold` is applied to `(max-min)/median(abs(values))`.
When the denominator is zero, identical zeros have zero spread and any nonzero
range has infinite relative spread. The default threshold is `0.25`; it is a
synthetic prototype default, not an empirically validated recommendation.

The implementation reports these conditions rather than repairing them:

- `within_family_divergence`: repeated values within one reference family exceed
  the threshold;
- `reference_type_divergence`: separately aggregated reference families disagree
  for the same channel, metric, and band;
- `missing_reference_family` and `insufficient_reference_count`: required
  evidence is absent or below `MinReferences`;
- `all_sources_excluded`: every selected row in the estimate group came from a
  QC-warning/failed analysis status under the default exclusion policy;
- `included_source_qc_warning`: `IncludeWarningSources=true` retained such
  source measurements explicitly;
- `included_failed_source`: `IncludeFailedSources=true` deliberately retained a
  numeric row owned by a failed source run; failed sources remain excluded by
  default and this exceptional policy is recorded;
- `unpaired_channel_references`: channels do not have the same reference IDs for
  a comparable metric/family/band;
- `incompatible_measurement_methods`: source method provenance differs.

The closed row-level `qc_status` vocabulary is `ok`,
`insufficient_evidence`, `divergent`, `source_qc_warning`, and
`not_comparable`. Detailed flags remain in JSON because several conditions can
coexist. Status precedence is non-comparability, retained source warning,
insufficiency, divergence, then OK. A profile run is `failed` if any estimate is
not comparable, `completed` only when every estimate is OK, and otherwise
`completed_with_warnings`.

Reference families are never averaged together. A declared median may still be
reported for a divergent within-family group, but its QC flag and descriptive
range remain attached. A required family with no values receives an explicit
estimate row with NULL `value_real`, zero sources, and insufficient-evidence QC.

## Lineage and retrieval

`channel_response_estimate_sources` names every supporting
`derived_measurement_id`. Its foreign key uses `ON DELETE RESTRICT`, so deleting
a measurement or its source analysis run cannot leave a surviving estimate.
Deleting the response-profile analysis run first cascades through estimates and
their junction rows while leaving source evidence intact.

The existing `analysis_run_sources` table also records every distinct included
response-measurement run with dependency role
`reference_response_measurement`. This provides run-level many-parent lineage in
addition to the exact measurement-level junction.

Schema triggers additionally require each source to match its estimate's
recording, channel, metric, reference type, and nullable frequency bounds. A
profile run cannot span recordings, and estimate identity updates cannot make
existing source links incompatible.

`vawlume.acoustic.readChannelResponse` resolves a profile by analysis-run ID or
portable project/run key and returns:

- analysis-run version, commit, status, and notes;
- every estimate and its full QC/details JSON;
- every exact supporting measurement with its acoustic reference and source-run
  provenance;
- the optional aggregation-policy profile assignment.

```matlab
profile = vawlume.acoustic.readChannelResponse(conn, ...
    struct(project_key="my-project", run_key="session01-response-profile"));
```

Planning is read-only. Applying the same run key and identical evidence/policy
reuses the stored rows. Any changed run provenance, estimate, source set, or
settings-profile assignment raises `ResponseProfileConflict`; no derived
evidence is silently updated.
