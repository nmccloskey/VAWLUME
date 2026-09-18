function value = edaChangeClasses()
%EDACHANGECLASSES How one agreement group can differ between two configurations.
%
% Group identity across configurations is EQUALITY OF THE MEMBER DETECTION-ID
% SET, never the stored group key. `agreement_groups` declares
% UNIQUE(analysis_run_id, group_key): the key is unique within a run and carries
% no cross-run meaning, so joining two configurations on it would produce a
% plausible, wrong answer in silence. Detection ids are upstream and stable.
%
%   retained      the identical member set exists on both sides
%   lost          a baseline group whose members appear in no comparison group
%   gained        a comparison group whose members appear in no baseline group
%   split         one group on this side corresponds to several on the other
%   merged        several groups on this side correspond to one on the other
%   reconfigured  an overlap that is neither identical, subset, nor superset
%
% `reconfigured` is named explicitly because it is the case most likely to be
% handled by accident: two groups that share some detections while neither
% contains the other are not a split, not a merge, and not unchanged, and
% folding them into any of those would misreport what the threshold did.
value = ["retained"; "lost"; "gained"; "split"; "merged"; "reconfigured"];
end
