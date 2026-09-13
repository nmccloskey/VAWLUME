function [plan, counts] = attributionApplyCorrespondencePlan(conn, plan)
%ATTRIBUTIONAPPLYCORRESPONDENCEPLAN Persist window-to-event correspondences.
%
% Every ambiguous correspondence is written. Nothing is resolved here, and the
% evidence rows record how good each correspondence was so a reviewer can weigh
% them rather than inherit a choice.

counts = struct(attribution_window_correspondences=0, attribution_evidence=0);

previousAutoCommit = conn.AutoCommit;
conn.AutoCommit = "off";
restore = onCleanup(@() restoreAutoCommit(conn, previousAutoCommit));

try
    for index = 1:height(plan.correspondences)
        row = plan.correspondences(index, :);
        values = struct( ...
            imported_attribution_window_id=double(row.imported_attribution_window_id), ...
            attribution_target_id=double(row.attribution_target_id), ...
            temporal_overlap_s=double(row.temporal_overlap_s), ...
            temporal_iou=double(row.temporal_iou), ...
            onset_difference_s=double(row.onset_difference_s), ...
            offset_difference_s=double(row.offset_difference_s), ...
            iou_basis=string(row.iou_basis), ...
            eligibility_rule=string(row.eligibility_rule), ...
            min_temporal_iou=double(row.min_temporal_iou));
        if ~isnan(double(row.alignment_run_id))
            values.alignment_run_id = double(row.alignment_run_id);
            values.aligned_start_s = double(row.aligned_start_s);
            values.aligned_end_s = double(row.aligned_end_s);
        end
        % The extrapolation flags survive into storage. A correspondence resting
        % on a time outside the transform's anchored range is weaker evidence,
        % and consuming the flag without recording it would hide that.
        if ~isnan(double(row.start_extrapolated))
            values.start_extrapolated = double(row.start_extrapolated);
        end
        if ~isnan(double(row.end_extrapolated))
            values.end_extrapolated = double(row.end_extrapolated);
        end
        attributionInsertRow(conn, "attribution_window_correspondences", ...
            values, "attribution_window_correspondence_id");
        counts.attribution_window_correspondences = ...
            counts.attribution_window_correspondences + 1;

        counts.attribution_evidence = counts.attribution_evidence + ...
            writeCorrespondenceEvidence(conn, plan, row);
    end
    if counts.attribution_window_correspondences > 0
        commit(conn);
    end
    % No correspondence survived the rule, so nothing opened a transaction.
    % sqlwrite opens one and execute only joins an open one, so committing here
    % would raise about a transaction that never existed -- and would replace a
    % legitimate empty result with an interface error.
catch exception
    try
        rollback(conn);
    catch
    end
    rethrow(exception);
end
clear restore
end

% ---------------------------------------------------------------- helpers ---

function written = writeCorrespondenceEvidence(conn, plan, row)
%WRITECORRESPONDENCEEVIDENCE How good was the correspondence this rests on?
%
% Target-level, because a correspondence is a statement about the event and the
% window rather than about any one candidate caller. The `correspondence`
% dimension exists for exactly this and combines with nothing.
basis = string(row.iou_basis);
semantics = "temporal IoU of the imported window against this event, computed " + ...
    "on " + basis + " intervals under " + string(row.eligibility_rule) + ...
    " with min_temporal_iou " + string(row.min_temporal_iou) + "; illustrative " + ...
    "and uncalibrated; not a probability that the window refers to this event";
if basis == "aligned"
    % Aligned duration is not native duration under a piecewise clock, so an
    % IoU computed on aligned intervals is not the IoU of the native ones. The
    % semantics say which, because the number alone cannot.
    semantics = semantics + "; aligned duration is not native duration under a " + ...
        "piecewise transform, so this is not the native-interval IoU";
end
if double(row.start_extrapolated) == 1 || double(row.end_extrapolated) == 1
    semantics = semantics + "; rests on an endpoint outside the transform's " + ...
        "anchored range";
end

values = struct( ...
    attribution_target_id=double(row.attribution_target_id), ...
    evidence_dimension="correspondence", ...
    evidence_kind="imported_window_temporal_iou", ...
    value_real=double(row.temporal_iou), ...
    value_units="fraction", ...
    value_semantics=semantics, ...
    source_locator="imported_attribution_window:" + string(row.native_window_id));
if ~isnan(double(row.alignment_run_id))
    values.alignment_run_id = double(row.alignment_run_id);
end
attributionInsertRow(conn, "attribution_evidence", values, "");
written = 1;
end

function restoreAutoCommit(conn, previous)
try
    conn.AutoCommit = previous;
catch
end
end
