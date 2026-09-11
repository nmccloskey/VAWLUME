function result = register(conn, recordingRef, trackingSpec, options)
%REGISTER Register one canonicalized tracking artifact as a logical stream.
%
%   result = VAWLUME.TRACKING.REGISTER(conn, recordingRef, trackingSpec)
%   result = VAWLUME.TRACKING.REGISTER(..., Apply=true)
%
% Tracking is an external stream, not a parallel ontology. This registers the
% logical stream, its artifact provenance, its clock, its declared spatial frame,
% the mapping profile that interprets it, the traces it contains, and its
% observed coverage — and **no tracking samples at all**.
%
% Positions, frames and confidences stay in the artifact and are read window-wise
% on demand. That is a hard boundary, not a default: nothing here writes a sample
% into SQLite, and no table exists that could hold one.
%
% TRACKINGSPEC requires:
%
%   artifact_path           the tracking export, absolute or SourceRoot-relative
%   profile_path            the tracking_input_mapping profile
%   timebase_key            an established timebase of this recording or project
%
% and optionally accepts profile_id (when the profile document holds several),
% stream_name (defaulting to the profile's stream_key), and notes.
%
% The coordinate system comes from the profile's context and **must already be
% declared** for the recording's project. Creating one implicitly would let an
% import choose its own units and dimensionality; compatibility is validated
% through vawlume.geometry.assertCompatible rather than assumed.
%
% Without Apply the call plans and returns what it would write, having read the
% artifact and resolved every reference, so a dry run shows the real registration
% rather than a guess. With Apply=true a conflict-free plan commits in one
% transaction.
%
% Re-registering identical content reuses the stream. Re-registering a stream key
% whose artifact checksum, frame, clock, or trace inventory differs reports a
% conflict and writes nothing, following the same rule the extractor importers
% and alignment intake already use.
%
% See also VAWLUME.SOURCE_MAPPING.MAPTABLETOIR, VAWLUME.GEOMETRY.ASSERTCOMPATIBLE

arguments
    conn
    recordingRef (1,1) struct
    trackingSpec (1,1) struct
    options.Apply (1,1) logical = false
    options.RepoRoot (1,1) string = ""
    options.SourceRoot (1,1) string = ""
    options.Table table = table()
end

plan = trackingBuildPlan(conn, recordingRef, trackingSpec, options);

if options.Apply
    if ~plan.ir.valid_for_ingest
        error("vawlume:tracking:NotReady", ...
            "The mapped tracking input is not ready for ingest. Structured " + ...
            "issues remain in the result; correct the artifact or the profile " + ...
            "rather than registering partial evidence.");
    end
    if ~plan.has_conflicts
        [plan, appliedCounts] = trackingApplyPlan(conn, plan);
        result = trackingPlanResult(plan);
        result.status = plan.status;
        result.committed = true;
        result.applied_counts = appliedCounts;
        return
    end
end

result = trackingPlanResult(plan);
end
