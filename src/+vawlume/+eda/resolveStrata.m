function result = resolveStrata(conn, recordingIds, options)
%RESOLVESTRATA Resolve contract §I's recording-level stratum fields for a frame.
%
% RESULT = vawlume.eda.RESOLVESTRATA(CONN, RECORDINGIDS) resolves every candidate
% stratum field the database already carries for those recordings. Supply
% Fields=[...] to resolve a named list instead of discovering them.
%
% The grammar is recording-level only (contract §I):
%
%   recording_attribute:<name>   recording_attributes value for that recording
%   entity_attribute:<name>      entity_attributes value via recording_entity_links
%   epoch:<epoch_type>           recording_epochs.epoch_name of that type
%   recording                    recordings.native_recording_id
%
% Name-value options:
%   Fields            explicit field specifications; default discovers them
%   IncludeRecording  admit the `recording` field during discovery, default
%                     false - it names one stratum per recording
%   OnMultiValued     "raise" or "reject" for a field that resolves to two
%                     values on one recording. Default "raise" when Fields
%                     names the field and "reject" when it was discovered
%
% ONE RESOLVER. This is the only stratum resolution in the MVP. A second
% implementation would eventually disagree with this one about what a recording's
% genotype is, and the disagreement would arrive as sampling bias with nothing in
% the output pointing at its cause.
%
% MISSING METADATA IS A REPRESENTED VALUE, NEVER A DROPPED ROW. Every requested
% recording appears in RESULT.recordings and carries a stratum value for every
% field, "(missing)" where the field does not resolve. A recording silently
% absent from the frame cannot be sampled and cannot be reported as unsampled.
%
% RESOLUTION DOES NOT GO THROUGH `v_recording_entity_context`. That view joins
% `recording_entity_links` and `experimental_entities` with inner JOINs, so a
% recording with no entity link vanishes from it entirely - it returns a clean,
% plausible, short answer, and the recordings it dropped are exactly the ones
% whose absence would bias the sample. Every query here LEFT JOINs from
% `recordings`, and the no-entity-link case is tested directly.
%
% A FIELD RESOLVING TO MORE THAN ONE DISTINCT VALUE FOR ONE RECORDING RAISES.
% `recording_entity_links` declares UNIQUE(recording_id, entity_id, link_type,
% role_label, start_time_s), which exists precisely so one recording can link
% several entities - a dyad recording links two animals and therefore has two
% sexes. Choosing one silently is how a stratified sample becomes wrong while
% still looking balanced. Several rows carrying the SAME value are one value and
% resolve normally; it is disagreement that raises.
%
% This function reads. It writes nothing, and it never reads an agreement,
% matching, or consilience table: a stratum may not be an output of the analysis
% the subset exists to probe.

arguments
    conn
    recordingIds double {mustBeVector}
    options.Fields string = strings(0, 1)
    options.IncludeRecording (1,1) logical = false
    options.OnMultiValued (1,1) string ...
        {mustBeMember(options.OnMultiValued, ["raise", "reject", "default"])} = "default"
end

ids = unique(double(recordingIds(:)));
if isempty(ids)
    error("vawlume:eda:StratumFrameEmpty", ...
        "No recording was supplied, so there is no sampling frame to " + ...
        "stratify. An empty frame is a caller defect, not an empty sample.");
end

recordings = fetchRecordings(conn, ids);
if isempty(options.Fields)
    specs = discoverFields(conn, ids, options.IncludeRecording);
else
    specs = options.Fields;
end

policy = multiValuedPolicy(options);
strata = emptyStrata();
summaries = emptyFieldSummary();
if ~isempty(specs)
    parsed = edaStratumGrammar(specs);
    for index = 1:height(parsed)
        [values, note] = resolveField(conn, ids, parsed(index, :), policy);
        strata = [strata; values]; %#ok<AGROW>
        summaries = [summaries; summarizeField(parsed.field(index), ...
            parsed.kind(index), values, note, numel(ids))]; %#ok<AGROW>
    end
end

result = struct( ...
    status="resolved", ...
    recording_count=height(recordings), ...
    recordings=recordings, ...
    strata=strata, ...
    fields=summaries, ...
    field_discovery=discoveryNote(options.Fields), ...
    multi_valued_policy=policy, ...
    missing_representation=edaMissingStratum(), ...
    ordering_key=edaFrameOrderingKey(), ...
    resolution_note="every field is resolved by an explicit LEFT JOIN from " + ...
        "recordings; v_recording_entity_context is not used, because its " + ...
        "inner joins drop a recording that has no entity link", ...
    forbidden_fields="a stratum may not be an extractor-support or " + ...
        "extractor-set field: those are outputs of the analysis the subset " + ...
        "exists to probe");
end

% -------------------------------------------------------------- the frame ---

function recordings = fetchRecordings(conn, ids)
%FETCHRECORDINGS The frame, in the stated ordering key, with nothing dropped.
rows = fetch(conn, "SELECT r.recording_id, " + ...
    "IFNULL(r.native_recording_id,'') AS native_recording_id " + ...
    "FROM recordings r WHERE r.recording_id IN (" + ...
    strjoin(string(ids'), ",") + ") ORDER BY r.recording_id");
recordings = table(double(rows.recording_id), ...
    edaPresentText(rows.native_recording_id), ...
    VariableNames=["recording_id", "native_recording_id"]);

absent = setdiff(ids, recordings.recording_id);
if ~isempty(absent)
    error("vawlume:eda:RecordingNotFound", ...
        "Recording(s) %s are not in the database. A frame quietly shorter " + ...
        "than requested would narrow the subset without saying so.", ...
        strjoin(string(absent'), ", "));
end
recordings = edaOrderFrame(recordings);
end

% --------------------------------------------------------- field discovery ---

function specs = discoverFields(conn, ids, includeRecording)
%DISCOVERFIELDS Every stratum field the metadata already supports.
%
% Discovered rather than configured, so the meaningfulness report in
% vawlume.eda.sampleRecordings names what the dataset actually offers and why
% each candidate was rejected. A caller who names fields explicitly bypasses
% this; a caller who names none gets the dataset's own vocabulary.
%
% `recording` is excluded by default. It resolves to a distinct value for every
% recording, so it passes coverage and distinctness while being no grouping at
% all, and the floor rule would then hand it the whole dataset.
scope = " IN (" + strjoin(string(ids'), ",") + ")";
specs = strings(0, 1);

rows = fetch(conn, "SELECT DISTINCT attribute_name FROM recording_attributes " + ...
    "WHERE recording_id" + scope + " ORDER BY attribute_name");
specs = [specs; distinctNames(rows, "attribute_name", "recording_attribute:")];

rows = fetch(conn, "SELECT DISTINCT ea.attribute_name AS attribute_name " + ...
    "FROM entity_attributes ea " + ...
    "JOIN recording_entity_links rel ON rel.entity_id=ea.entity_id " + ...
    "WHERE rel.recording_id" + scope + " ORDER BY ea.attribute_name");
specs = [specs; distinctNames(rows, "attribute_name", "entity_attribute:")];

rows = fetch(conn, "SELECT DISTINCT IFNULL(epoch_type,'') AS epoch_type " + ...
    "FROM recording_epochs WHERE recording_id" + scope + " ORDER BY 1");
specs = [specs; distinctNames(rows, "epoch_type", "epoch:")];

if includeRecording
    specs = [specs; "recording"];
end
specs = specs(:);
end

function values = distinctNames(rows, column, prefix)
if isempty(rows) || height(rows) == 0
    values = strings(0, 1);
    return
end
names = edaPresentText(rows.(column));
names = strtrim(names(:));
values = prefix + names(strlength(names) > 0);
end

% ------------------------------------------------------- field resolution ---

function policy = multiValuedPolicy(options)
%MULTIVALUEDPOLICY What to do with a field that resolves to two values at once.
%
% A NAMED FIELD RAISES; A DISCOVERED FIELD IS REJECTED. Contract §I's rule is
% about a field the caller asked for: silently picking one of a dyad's two sexes
% is how a stratified sample becomes wrong, so that must stop the run. Discovery
% is the other situation - the resolver is enumerating what the dataset happens
% to carry, and one unusable candidate among several should not destroy the
% usable ones. The pilot fixture is exactly this case: a dyad recording carries
% two sexes, and under a raising discovery no field would resolve at all.
%
% Rejected is not silent. The field appears in RESULT.fields with
% `is_resolvable` false and a note naming the recording and the disagreement, so
% the subset record still reports why it was not used.
if options.OnMultiValued ~= "default"
    policy = options.OnMultiValued;
    return
end
policy = "reject";
if ~isempty(options.Fields)
    policy = "raise";
end
end

function [values, note] = resolveField(conn, ids, spec, policy)
%RESOLVEFIELD One stratum value per recording for one field.
%
% The rendering happens in SQL rather than in MATLAB for a blunt reason: this
% interface cannot return a NULL text column, and a nullable column reached
% through a LEFT JOIN is null for exactly the recordings this function exists to
% keep. Every column comes back as present text, and absence is a value.
scope = " IN (" + strjoin(string(ids'), ",") + ")";
switch spec.kind
    case "recording_attribute"
        query = "SELECT r.recording_id, " + ...
            typedValueExpression("ra") + " AS stratum_value " + ...
            "FROM recordings r LEFT JOIN recording_attributes ra " + ...
            "ON ra.recording_id=r.recording_id " + ...
            "AND ra.attribute_name=" + edaSqlText(spec.name) + " " + ...
            "WHERE r.recording_id" + scope;
    case "entity_attribute"
        % Two LEFT JOINs, and the attribute-name predicate lives in the ON
        % clause. Moving it to WHERE would turn the outer join back into an
        % inner one and reintroduce exactly the drop this grammar forbids.
        query = "SELECT r.recording_id, " + ...
            typedValueExpression("ea") + " AS stratum_value " + ...
            "FROM recordings r " + ...
            "LEFT JOIN recording_entity_links rel " + ...
            "ON rel.recording_id=r.recording_id " + ...
            "LEFT JOIN entity_attributes ea ON ea.entity_id=rel.entity_id " + ...
            "AND ea.attribute_name=" + edaSqlText(spec.name) + " " + ...
            "WHERE r.recording_id" + scope;
    case "epoch"
        query = "SELECT r.recording_id, " + ...
            "IFNULL(re.epoch_name,'') AS stratum_value " + ...
            "FROM recordings r LEFT JOIN recording_epochs re " + ...
            "ON re.recording_id=r.recording_id " + ...
            "AND re.epoch_type=" + edaSqlText(spec.name) + " " + ...
            "WHERE r.recording_id" + scope;
    case "recording"
        query = "SELECT r.recording_id, " + ...
            "IFNULL(r.native_recording_id,'') AS stratum_value " + ...
            "FROM recordings r WHERE r.recording_id" + scope;
    otherwise
        error("vawlume:eda:StratumFieldInvalid", ...
            "Field kind '%s' has no resolver.", spec.kind);
end

rows = fetch(conn, query + " ORDER BY r.recording_id");
raw = table(double(rows.recording_id), edaPresentText(rows.stratum_value), ...
    VariableNames=["recording_id", "stratum_value"]);
note = "";
try
    values = reduceToOnePerRecording(raw, ids, spec.field);
catch err
    if err.identifier ~= "vawlume:eda:StratumNotUnique" || policy == "raise"
        rethrow(err);
    end
    values = emptyStrata();
    note = string(err.message);
end
end

function expression = typedValueExpression(alias)
%TYPEDVALUEEXPRESSION Render an attribute row's declared value type as text.
%
% `value_type` says which of the six value columns holds the value, and the
% table's CHECK constraint guarantees exactly one is populated. Reading
% `value_text` alone would silently return "(missing)" for every integer or
% boolean attribute - a whole field looking absent because it was stored in the
% column its own type declaration names.
expression = "CASE " + ...
    "WHEN " + alias + ".value_type IS NULL THEN '' " + ...
    "WHEN " + alias + ".value_type='missing' THEN '' " + ...
    "WHEN " + alias + ".value_type='text' THEN IFNULL(" + alias + ".value_text,'') " + ...
    "WHEN " + alias + ".value_type='real' THEN " + ...
    "IFNULL(CAST(" + alias + ".value_real AS TEXT),'') " + ...
    "WHEN " + alias + ".value_type='integer' THEN " + ...
    "IFNULL(CAST(" + alias + ".value_integer AS TEXT),'') " + ...
    "WHEN " + alias + ".value_type='boolean' THEN " + ...
    "CASE " + alias + ".value_boolean WHEN 1 THEN 'true' " + ...
    "WHEN 0 THEN 'false' ELSE '' END " + ...
    "WHEN " + alias + ".value_type='json' THEN " + ...
    "IFNULL(" + alias + ".value_json,'') " + ...
    "ELSE '' END";
end

function values = reduceToOnePerRecording(raw, ids, field)
%REDUCETOONEPERRECORDING Exactly one stratum value per recording, or raise.
missingValue = edaMissingStratum();
values = emptyStrata();
for index = 1:numel(ids)
    id = ids(index);
    selected = raw(raw.recording_id == id, :);
    present = strtrim(selected.stratum_value);
    present = present(strlength(present) > 0);
    distinct = unique(present);
    if numel(distinct) > 1
        error("vawlume:eda:StratumNotUnique", ...
            "Recording %d resolves field '%s' to %d distinct values (%s). " + ...
            "A recording may link several entities by design, so one " + ...
            "recording can carry two genotypes or two sexes; choosing one " + ...
            "silently is how a stratified sample becomes wrong while still " + ...
            "looking balanced. Name a field that resolves uniquely, or " + ...
            "narrow the frame.", ...
            id, field, numel(distinct), strjoin("'" + distinct' + "'", ", "));
    end
    if isempty(distinct)
        values(end + 1, :) = {id, field, missingValue, true}; %#ok<AGROW>
    else
        values(end + 1, :) = {id, field, distinct(1), false}; %#ok<AGROW>
    end
end
end

% ------------------------------------------------------------- summaries ---

function summary = summarizeField(field, kind, values, note, frameSize)
%SUMMARIZEFIELD The counts the meaningfulness decision is made from.
%
% `distinct_value_count` counts NON-MISSING values; `stratum_count` counts the
% strata the allocator would actually face, which includes "(missing)". They are
% reported separately because the qualification rule reads the first and the
% allocation reads the second, and collapsing them would make a field with one
% real value plus a missing group look like a two-way split.
if strlength(note) > 0
    % Unresolvable under the "reject" policy. Reported with the frame's own
    % recording count and zero coverage, so the qualification rule rejects it on
    % its stated criteria as well as on `is_resolvable`, and the note carries
    % the recording and the disagreement into the subset record.
    summary = table(field, kind, frameSize, 0, frameSize, 0, 0, 0, "", 0, ...
        false, note, ...
        VariableNames=fieldSummaryNames());
    return
end
total = height(values);
resolved = nnz(~values.is_missing);
distinct = unique(values.stratum_value(~values.is_missing));

largestShare = 0;
largestValue = "";
if total > 0
    [groups, ~, grouping] = unique(values.stratum_value);
    occurrences = accumarray(grouping, 1);
    [peak, at] = max(occurrences);
    largestShare = peak / total;
    largestValue = groups(at);
end

coverageFraction = 0;
if total > 0
    coverageFraction = resolved / total;
end

summary = table(field, kind, total, resolved, total - resolved, ...
    coverageFraction, numel(distinct), ...
    numel(unique(values.stratum_value)), largestValue, largestShare, ...
    true, "", VariableNames=fieldSummaryNames());
end

function value = fieldSummaryNames()
value = ["field", "kind", "recording_count", "resolved_count", ...
    "missing_count", "coverage_fraction", "distinct_value_count", ...
    "stratum_count", "largest_stratum", "largest_stratum_share", ...
    "is_resolvable", "resolution_note"];
end

% -------------------------------------------------------------- plumbing ---

function value = discoveryNote(supplied)
if isempty(supplied)
    value = "fields discovered from recording_attributes, entity_attributes " + ...
        "reachable through recording_entity_links, and recording_epochs";
    return
end
value = "fields supplied explicitly by the caller";
end

function value = emptyStrata()
value = table(zeros(0, 1), strings(0, 1), strings(0, 1), false(0, 1), ...
    VariableNames=["recording_id", "field", "stratum_value", "is_missing"]);
end

function value = emptyFieldSummary()
value = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    zeros(0, 1), false(0, 1), strings(0, 1), ...
    VariableNames=fieldSummaryNames());
end
