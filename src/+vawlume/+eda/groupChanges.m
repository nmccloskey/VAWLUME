function result = groupChanges(baselineMembers, comparisonMembers, options)
%GROUPCHANGES Classify how agreement groups differ between two configurations.
%
% RESULT = vawlume.eda.GROUPCHANGES(BASELINEMEMBERS, COMPARISONMEMBERS) takes two
% cell arrays, each holding one vector of member detection ids per agreement
% group, and classifies every group on both sides.
%
% GROUP IDENTITY IS THE MEMBER DETECTION-ID SET. It is never the stored group
% key: `agreement_groups` declares UNIQUE(analysis_run_id, group_key), so the key
% is unique within one analysis and carries no meaning across two. Joining two
% configurations on it would produce a plausible, wrong answer in silence, which
% is why this function takes detection ids and why the response layer refuses a
% group_key comparison outright.
%
% Both sides are classified, because the question is asymmetric. A baseline group
% that became three comparison groups is a `split` seen from the baseline; those
% three are one `merged` target each seen from the comparison. Reporting only one
% side would lose the count on the other, and both counts enter the screen's
% effect estimates.
%
% RESULT.from_classes and RESULT.to_classes give one class per group, so each
% side partitions exactly: every baseline group has exactly one class and every
% comparison group has exactly one class. RESULT.counts reports both sides, and
% the partition is asserted rather than assumed.
%
% THERE IS NO RETENTION SCORE. The classes are reported as separate counts. A
% retention fraction may accompany them elsewhere with its denominator stated,
% but collapsing six distinct outcomes into one number is the composite score the
% exploratory framing forbids.

arguments
    baselineMembers cell
    comparisonMembers cell
    options.RequireSamePopulation (1,1) logical = false
end

from = normalize(baselineMembers);
to = normalize(comparisonMembers);
population = assertPopulation(from, to, options.RequireSamePopulation);
overlap = overlapMatrix(from, to);

fromClasses = classifySide(from, to, overlap, "from");
toClasses = classifySide(to, from, overlap', "to");

assertPartition(fromClasses, numel(from), "baseline");
assertPartition(toClasses, numel(to), "comparison");

result = struct( ...
    status="classified", ...
    from_group_count=numel(from), ...
    to_group_count=numel(to), ...
    from_classes=fromClasses, ...
    to_classes=toClasses, ...
    counts=countTable(fromClasses, toClasses), ...
    class_vocabulary=edaChangeClasses()', ...
    identity_rule="equality of the member detection-id set", ...
    population=population, ...
    retained_group_count=nnz(fromClasses == "retained"));
end

function population = assertPopulation(from, to, required)
%ASSERTPOPULATION Whether both sides describe the same detections.
%
% Two configurations of one agreement analysis partition the SAME node set: the
% groups are built over every detection of the participating extraction runs, and
% a threshold changes how those detections connect, never which exist. When that
% holds, `lost` and `gained` cannot occur - every group necessarily overlaps
% something on the other side - so seeing either from a real probe means the two
% sides describe different recordings or different runs.
%
% Enforced only on request, because this function is also the general-purpose
% classifier and the vocabulary covers cases a caller may legitimately construct.
fromPopulation = unique([from{:}]);
toPopulation = unique([to{:}]);
population = struct( ...
    baseline_detection_count=numel(fromPopulation), ...
    comparison_detection_count=numel(toPopulation), ...
    is_same_population=isequal(fromPopulation, toPopulation));
if required && ~population.is_same_population
    error("vawlume:eda:ChangePopulationMismatch", ...
        "The two configurations describe different detection populations " + ...
        "(%d and %d detections). Two configurations of one agreement " + ...
        "analysis partition the same detections, so a mismatch means the " + ...
        "sides are not comparable rather than that the grouping changed.", ...
        numel(fromPopulation), numel(toPopulation));
end
end

function classes = classifySide(side, other, overlap, which)
%CLASSIFYSIDE One class per group on this side, in a fixed precedence.
%
% Precedence matters and runs identity first: a group whose member set exists
% unchanged on the other side is retained even if it also happens to overlap a
% second group, because identity is the strongest statement available and
% anything weaker would understate what the configurations agree on.
count = numel(side);
classes = strings(count, 1);
for index = 1:count
    partners = find(overlap(index, :));
    mine = side{index};
    if any(arrayfun(@(p) isequal(mine, other{p}), partners))
        classes(index) = "retained";
        continue
    end
    if isempty(partners)
        if which == "from"
            classes(index) = "lost";
        else
            classes(index) = "gained";
        end
        continue
    end
    containsAll = arrayfun(@(p) all(ismember(other{p}, mine)), partners);
    containedBy = arrayfun(@(p) all(ismember(mine, other{p})), partners);
    if all(containsAll)
        % Every overlapping group on the other side sits inside this one, so
        % this group's membership was divided. The partner count is not part of
        % the test: a group that shed members to one visible partner divided
        % just as surely as one that shed them to three, and the contract
        % reserves `reconfigured` for overlaps that are neither subset nor
        % superset.
        classes(index) = splitOrMerge(which, "source");
    elseif isscalar(partners) && containedBy(1)
        % This group is part of a larger group on the other side.
        classes(index) = splitOrMerge(which, "target");
    else
        classes(index) = "reconfigured";
    end
end
end

function value = splitOrMerge(which, role)
%SPLITORMERGE The same event has opposite names from the two sides.
%
% One baseline group becoming several is a split when seen from the baseline and
% a merge when seen from the comparison groups looking back. Naming it from the
% side being classified is what makes each side's counts add up on their own.
if which == "from"
    if role == "source"
        value = "split";
    else
        value = "merged";
    end
else
    if role == "source"
        value = "merged";
    else
        value = "split";
    end
end
end

function value = overlapMatrix(from, to)
value = false(numel(from), numel(to));
for left = 1:numel(from)
    for right = 1:numel(to)
        value(left, right) = ~isempty(intersect(from{left}, to{right}));
    end
end
end

function value = normalize(members)
value = cell(numel(members), 1);
for index = 1:numel(members)
    entry = members{index};
    if isstring(entry) || ischar(entry) || iscellstr(entry)
        % Almost certainly group keys. `agreement_groups` declares
        % UNIQUE(analysis_run_id, group_key), so a key is unique within one
        % analysis and means nothing across two: comparing configurations on it
        % would match unrelated groups and report a plausible, wrong answer
        % without failing. Detection ids are upstream and stable, so they are
        % the only identity this function accepts.
        error("vawlume:eda:GroupKeyComparisonRefused", ...
            "Group %d was supplied as text. Groups are compared by member " + ...
            "detection id, never by group_key: a group key is unique within " + ...
            "one analysis run and carries no meaning across two.", index);
    end
    if isempty(entry)
        error("vawlume:eda:GroupMembersEmpty", ...
            "Group %d has no member detection, so it has no identity to " + ...
            "compare. Every agreement group carries at least one member.", ...
            index);
    end
    value{index} = reshape(unique(double(entry)), 1, []);
end
end

function assertPartition(classes, expected, side)
if numel(classes) ~= expected || any(strlength(classes) == 0)
    error("vawlume:eda:ChangeClassificationIncomplete", ...
        "The %s side did not receive exactly one class per group.", side);
end
if ~all(ismember(classes, edaChangeClasses()))
    error("vawlume:eda:ChangeClassUnknown", ...
        "The %s side produced a class outside the fixed vocabulary.", side);
end
end

function value = countTable(fromClasses, toClasses)
classes = edaChangeClasses();
fromCount = zeros(numel(classes), 1);
toCount = zeros(numel(classes), 1);
for index = 1:numel(classes)
    fromCount(index) = nnz(fromClasses == classes(index));
    toCount(index) = nnz(toClasses == classes(index));
end
value = table(classes, fromCount, toCount, ...
    VariableNames=["change_class", "from_side", "to_side"]);
end
