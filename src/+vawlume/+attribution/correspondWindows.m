function result = correspondWindows(conn, runRef, options)
%CORRESPONDWINDOWS Relate imported attribution windows to VAWLUME events.
%
% RESULT = VAWLUME.ATTRIBUTION.CORRESPONDWINDOWS(CONN, RUNREF) previews which
% imported windows of a run plausibly refer to which of its target events,
% without writing. Apply=true persists the correspondences atomically.
%
% This asks whether an attribution claim refers to a call VAWLUME knows about.
% That is **not** the question detector-to-detector matching asks, and it does
% not share its rule: two detectors disagreeing is a measurement difference,
% while an attribution system's window disagreeing with a VAWLUME event may mean
% the two systems were segmenting different things. The eligibility rule is
% declared in the attribution mapping profile the import registered.
%
% CLOCKS. An imported window carries the exporting system's own native times;
% intake resolves them against no timebase. So the caller must say, explicitly,
% how the two clocks relate:
%
%   AlignmentRun = <id>   transform the window onto the target's clock through
%                         VAWLUME.ALIGNMENT.APPLYTRANSFORMINTERVAL, and record
%                         iou_basis 'aligned'
%   SameClock = true      assert that the exporter used the recording's clock,
%                         and record iou_basis 'native'
%
% Exactly one is required. Neither defaulting nor guessing is offered, because a
% correspondence computed on incomparable clocks is a plausible number and a
% wrong one, and nothing downstream could tell.
%
% **Aligned duration is not native duration** under a piecewise clock, so an IoU
% computed on aligned intervals is not the IoU of the native ones. Every stored
% row says which basis it used.
%
% **An extrapolated endpoint survives into storage.** A correspondence resting on
% a time outside the transform's anchored range is weaker evidence, and dropping
% the flag after using it would hide that.
%
% **Ambiguity is preserved.** A window plausibly referring to two events produces
% two correspondences, both stored with their scores. Nothing here chooses; a
% reviewer does, with the evidence in front of them.
%
% **An agreement-group target names the extent basis its interval came from**, in
% `target_extent_basis` on every returned row, and RESULT.extent_bases lists the
% bases the run spans. This is a different fact from `iou_basis`: the extent
% basis says which of the five derivations gave the group an interval at all,
% while `iou_basis` says whether the IoU was computed on native or aligned times.
% Results on different extent bases are not comparable and must not be pooled.
%
% **An applied run is not applied twice.** A second Apply is refused by name
% (`vawlume:attribution:CorrespondenceAlreadyApplied`) because evidence is
% append-only. Planning still works on an applied run.
%
% Name-value arguments:
%   Apply         persist the correspondences (default false)
%   AlignmentRun  transform run relating the exporter's clock to the target's
%   SameClock     assert both are already on one clock (default false)
%   RepoRoot      repository root, inferred from this file by default
%
% See also VAWLUME.INGEST.ATTRIBUTION, VAWLUME.ALIGNMENT.APPLYTRANSFORMINTERVAL,
% VAWLUME.INTERVAL.RELATION

arguments
    conn
    runRef (1,1) struct
    options.Apply (1,1) logical = false
    options.AlignmentRun double = []
    options.SameClock (1,1) logical = false
    options.RepoRoot (1,1) string = ""
end

plan = attributionBuildCorrespondencePlan(conn, runRef, options);
result = correspondenceResult(plan);
if options.Apply
    [plan, counts] = attributionApplyCorrespondencePlan(conn, plan);
    result = correspondenceResult(plan);
    result.committed = true;
    result.applied_counts = counts;
    result.status = "corresponded";
end
end

function result = correspondenceResult(plan)
result = struct( ...
    status="planned", ...
    committed=false, ...
    attribution_run_id=plan.run.attribution_run_id, ...
    run_key=plan.run.run_key, ...
    iou_basis=plan.iou_basis, ...
    alignment_run_id=plan.alignment_run_id, ...
    rule=plan.rule, ...
    extent_bases=plan.extent_bases, ...
    correspondences=plan.correspondences, ...
    considered_pairs=plan.considered_pairs, ...
    windows_without_correspondence=plan.windows_without_correspondence, ...
    ambiguous_window_count=plan.ambiguous_window_count, ...
    boundary="A correspondence says an imported window plausibly refers to this " + ...
        "event. It does not say the claimed caller called, and it is not a " + ...
        "detector agreement.", ...
    does_not_prove=["that the imported window and the event are the same call"; ...
        "that the eligibility threshold is calibrated"; ...
        "that an unmatched window refers to nothing"]);
end
