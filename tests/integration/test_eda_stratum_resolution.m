function tests = test_eda_stratum_resolution
%TEST_EDA_STRATUM_RESOLUTION Contract §I's stratum grammar against real metadata.
%
% Integration tier, because the defect this part exists to prevent is a JOIN
% defect: a recording with no entity link vanishing from the sampling frame. That
% cannot be reproduced against a hand-built table - it needs the relational
% mechanisms the resolver actually queries.
tests = functiontests({ ...
    @testEveryAdmittedFieldKindResolves, ...
    @testARecordingWithNoEntityLinkStaysInTheFrameAsMissing, ...
    @testTheEntityContextViewWouldHaveDroppedThatRecording, ...
    @testMissingMetadataIsARepresentedValueNotADroppedRow, ...
    @testANamedMultiValuedFieldRaisesNamingRecordingAndField, ...
    @testADiscoveredMultiValuedFieldIsRejectedWithItsReason, ...
    @testNonTextAttributeTypesResolveFromTheirOwnValueColumn, ...
    @testSupportPatternAndExtractorSetAreRefusedByName, ...
    @testUnknownFieldKindsAreRefused, ...
    @testDiscoveryFindsTheDatasetsOwnVocabulary, ...
    @testTheMeaningfulnessDecisionPicksTheMostBalancedField, ...
    @testEveryRejectedFieldCarriesItsReason, ...
    @testStratifiedDrawPreservesTheRareMissingStratum, ...
    @testNothingInThisPartWritesToTheDatabase});
end

% ------------------------------------------------------------ the grammar ---

function testEveryAdmittedFieldKindResolves(testCase)
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12, ...
    Fields=["recording_attribute:genotype"; "entity_attribute:strain"; ...
    "epoch:phase"; "recording"]);

verifyEqual(testCase, height(resolved.fields), 4);
verifyEqual(testCase, resolved.fields.kind, ["recording_attribute"; ...
    "entity_attribute"; "epoch"; "recording"]);

% Each kind reaches its own table, so each returns a different partition.
verifyEqual(testCase, stratumOf(resolved, "recording_attribute:genotype", 1), "WT");
verifyEqual(testCase, stratumOf(resolved, "recording_attribute:genotype", 7), "KO");
verifyEqual(testCase, stratumOf(resolved, "entity_attribute:strain", 10), "CD1");
verifyEqual(testCase, stratumOf(resolved, "epoch:phase", 5), "late");
verifyEqual(testCase, stratumOf(resolved, "epoch:phase", 1), "early");
verifyEqual(testCase, stratumOf(resolved, "recording", 3), "REC_03");

% Every field resolves every recording. A field that answered for only the
% recordings it happened to cover would shrink the frame silently.
for field = resolved.fields.field'
    verifyEqual(testCase, nnz(resolved.strata.field == field), 12, ...
        "Field " + field + " did not answer for all twelve recordings.");
end
end

% ------------------------------- the trap this section exists to prevent ---

function testARecordingWithNoEntityLinkStaysInTheFrameAsMissing(testCase)
%TESTARECORDINGWITHNOENTITYLINK... The specific bias contract §I documents.
%
% REC_12 has no row in `recording_entity_links` at all. It must still appear in
% the frame, and its entity-attribute stratum must be the missing representation.
% A resolver that dropped it would return eleven plausible rows and bias every
% subsequent sample towards recordings that happen to carry entity metadata.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12, ...
    Fields="entity_attribute:strain");

verifyEqual(testCase, height(resolved.recordings), 12);
verifyTrue(testCase, ismember(12, resolved.recordings.recording_id));
verifyEqual(testCase, stratumOf(resolved, "entity_attribute:strain", 12), ...
    "(missing)");
verifyTrue(testCase, resolved.strata.is_missing( ...
    resolved.strata.recording_id == 12));
end

function testTheEntityContextViewWouldHaveDroppedThatRecording(testCase)
%TESTTHEENTITYCONTEXTVIEWWOULDHAVEDROPPED... Negative result, held in a test.
%
% This is the observed failure behind the previous test. `v_recording_entity_context`
% inner-joins recording_entity_links and experimental_entities, so it answers for
% eleven of twelve recordings and looks entirely healthy doing it. Asserting the
% view's own shortfall here keeps the reason for the LEFT JOIN visible: if a
% future edit reaches for the convenient view, this test states what that costs.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
throughView = fetch(conn, "SELECT DISTINCT recording_id FROM " + ...
    "v_recording_entity_context ORDER BY recording_id");

verifyEqual(testCase, height(throughView), 11);
verifyFalse(testCase, ismember(12, double(throughView.recording_id)));

% And the resolver does not consult it.
source = fileread(fullfile(repoRootPath(), "src", "+vawlume", "+eda", ...
    "resolveStrata.m"));
verifyEqual(testCase, numel(strfind(source, "FROM v_recording_entity_context")), 0);
end

function testMissingMetadataIsARepresentedValueNotADroppedRow(testCase)
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12, ...
    Fields=["recording_attribute:genotype"; "recording_attribute:rig"]);

verifyEqual(testCase, resolved.missing_representation, "(missing)");
% REC_12 carries no genotype row; six recordings carry no rig row.
verifyEqual(testCase, stratumOf(resolved, "recording_attribute:genotype", 12), ...
    "(missing)");
genotype = resolved.fields(resolved.fields.field == ...
    "recording_attribute:genotype", :);
verifyEqual(testCase, genotype.missing_count, 1);
verifyEqual(testCase, genotype.resolved_count, 11);
verifyEqual(testCase, genotype.stratum_count, 3);
verifyEqual(testCase, genotype.distinct_value_count, 2);

rig = resolved.fields(resolved.fields.field == "recording_attribute:rig", :);
verifyEqual(testCase, rig.missing_count, 6);
verifyEqual(testCase, rig.coverage_fraction, 0.5, AbsTol=1e-12);
end

% -------------------------------------------------- multi-valued resolution ---

function testANamedMultiValuedFieldRaisesNamingRecordingAndField(testCase)
%TESTANAMEDMULTIVALUEDFIELDRAISES... REC_01 links a male and a female.
%
% `recording_entity_links` permits several entities per recording by design, so
% this is a normal dyad recording, not corrupt data. Picking one sex silently is
% how a stratified sample becomes wrong while still looking balanced.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
handle = @() vawlume.eda.resolveStrata(conn, 1:12, ...
    Fields="entity_attribute:sex");
verifyError(testCase, handle, "vawlume:eda:StratumNotUnique");

try
    handle();
catch err
    % The message has to name both, or the reader cannot find the recording.
    verifySubstring(testCase, err.message, "Recording 1");
    verifySubstring(testCase, err.message, "entity_attribute:sex");
    verifySubstring(testCase, err.message, "'female'");
    verifySubstring(testCase, err.message, "'male'");
end
end

function testADiscoveredMultiValuedFieldIsRejectedWithItsReason(testCase)
%TESTADISCOVEREDMULTIVALUEDFIELDISREJECTED... A candidate, not a request.
%
% During discovery the resolver is enumerating what the dataset happens to carry.
% One ambiguous candidate must not destroy the usable ones - and the rejection is
% still not silent: it carries the raising message, recording id included.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12);
verifyEqual(testCase, resolved.multi_valued_policy, "reject");

sex = resolved.fields(resolved.fields.field == "entity_attribute:sex", :);
verifyEqual(testCase, height(sex), 1);
verifyFalse(testCase, sex.is_resolvable);
verifySubstring(testCase, sex.resolution_note, "Recording 1");

% The other fields survived.
genotype = resolved.fields(resolved.fields.field == ...
    "recording_attribute:genotype", :);
verifyTrue(testCase, genotype.is_resolvable);
end

function testNonTextAttributeTypesResolveFromTheirOwnValueColumn(testCase)
%TESTNONTEXTATTRIBUTETYPESRESOLVE... `value_type` says where the value lives.
%
% `recording_attributes` spreads values across six typed columns and a CHECK
% constraint guarantees exactly one is populated. A resolver reading value_text
% alone would report a whole integer-valued field as absent, which reads as
% missing metadata rather than as a defect.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12, ...
    Fields=["recording_attribute:batch"; "recording_attribute:is_pilot"]);

verifyEqual(testCase, stratumOf(resolved, "recording_attribute:batch", 1), "1");
verifyEqual(testCase, stratumOf(resolved, "recording_attribute:batch", 12), "2");
verifyEqual(testCase, stratumOf(resolved, "recording_attribute:is_pilot", 1), ...
    "true");
verifyEqual(testCase, stratumOf(resolved, "recording_attribute:is_pilot", 2), ...
    "false");

batch = resolved.fields(resolved.fields.field == "recording_attribute:batch", :);
verifyEqual(testCase, batch.coverage_fraction, 1, AbsTol=1e-12);
end

% ---------------------------------------------- fields outside the grammar ---

function testSupportPatternAndExtractorSetAreRefusedByName(testCase)
%TESTSUPPORTPATTERNANDEXTRACTORSETAREREFUSED... Deleted, not merely unknown.
%
% Support pattern is an OUTPUT of the correspondence analysis the subset exists
% to probe. Stratifying on it would condition the sample on the thing being
% measured. Both were in the calibration-era grammar, so a carried-forward
% configuration will name one and needs to be told why it is gone.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
for spec = ["support_pattern", "extractor_set", "support_pattern:exact"]
    handle = @() vawlume.eda.resolveStrata(conn, 1:12, Fields=spec);
    verifyError(testCase, handle, "vawlume:eda:StratumFieldForbidden", ...
        "Field '" + spec + "' was admitted.");
end

try
    vawlume.eda.resolveStrata(conn, 1:12, Fields="support_pattern");
catch err
    verifySubstring(testCase, err.message, "outputs of the correspondence analysis");
end

% Discovery never proposes one either.
resolved = vawlume.eda.resolveStrata(conn, 1:12);
verifyFalse(testCase, any(contains(resolved.fields.field, "support_pattern")));
verifyFalse(testCase, any(contains(resolved.fields.field, "extractor_set")));
end

function testUnknownFieldKindsAreRefused(testCase)
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
for spec = ["detection_attribute:x", "genotype", "epoch:", ":phase"]
    verifyError(testCase, ...
        @() vawlume.eda.resolveStrata(conn, 1:12, Fields=spec), ...
        "vawlume:eda:StratumFieldInvalid", "Field '" + spec + "' was admitted.");
end
verifyError(testCase, @() vawlume.eda.resolveStrata(conn, 1:12, ...
    Fields=["epoch:phase"; "epoch:phase"]), ...
    "vawlume:eda:StratumFieldDuplicated");
end

% -------------------------------------------- the meaningfulness decision ---

function testDiscoveryFindsTheDatasetsOwnVocabulary(testCase)
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12);

verifyTrue(testCase, all(ismember(["recording_attribute:genotype", ...
    "recording_attribute:cohort", "recording_attribute:rig", ...
    "entity_attribute:strain", "entity_attribute:sex", "epoch:phase"], ...
    resolved.fields.field)));

% `recording` is not proposed. It takes a distinct value on every recording, so
% it passes coverage and distinctness while being no grouping at all, and the
% floor of one per stratum would then select the entire dataset.
verifyFalse(testCase, ismember("recording", resolved.fields.field));
withRecording = vawlume.eda.resolveStrata(conn, 1:12, IncludeRecording=true);
verifyTrue(testCase, ismember("recording", withRecording.fields.field));
end

function testTheMeaningfulnessDecisionPicksTheMostBalancedField(testCase)
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12);
subset = vawlume.eda.sampleRecordings(resolved, Seed=11);

verifyTrue(testCase, subset.is_stratified);
verifyEqual(testCase, subset.stratum_field, "recording_attribute:genotype");
verifySubstring(testCase, subset.stratification_statement, "Stratified on");

considered = subset.fields_considered;
% genotype splits 6/5/1 - dominance 0.50; phase splits 7/5 - dominance 0.58;
% strain splits 10/1/1 - dominance 0.83. All three qualify and the most evenly
% divided wins, so the others are recorded as qualified-but-not-selected rather
% than as failures.
qualifying = considered.field(considered.qualifies);
verifyEqual(testCase, sort(qualifying), sort(["recording_attribute:genotype"; ...
    "entity_attribute:strain"; "epoch:phase"]));
notSelected = considered(considered.qualifies & ~considered.is_selected, :);
verifyTrue(testCase, all(startsWith(notSelected.rejection_reason, ...
    "qualified_but_not_selected")));
end

function testEveryRejectedFieldCarriesItsReason(testCase)
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12, IncludeRecording=true);
subset = vawlume.eda.sampleRecordings(resolved, Seed=11);
considered = subset.fields_considered;

% The decision is automatic, so every row must be re-derivable from the record.
verifyTrue(testCase, all(strlength(considered.rejection_reason( ...
    ~considered.is_selected)) > 0));
verifyEqual(testCase, strlength(considered.rejection_reason( ...
    considered.is_selected)), 0);

verifySubstring(testCase, reasonFor(considered, "recording_attribute:cohort"), ...
    "fewer_than_2_distinct_values");
verifySubstring(testCase, reasonFor(considered, "recording_attribute:rig"), ...
    "coverage_below_minimum");
verifySubstring(testCase, reasonFor(considered, "entity_attribute:sex"), ...
    "not_uniquely_resolvable");
verifySubstring(testCase, reasonFor(considered, "recording"), ...
    "every_recording_in_its_own_stratum");
verifySubstring(testCase, reasonFor(considered, "recording_attribute:batch"), ...
    "dominant_stratum_exceeds_maximum_share");
end

% ------------------------------------------------------------ the draw ---

function testStratifiedDrawPreservesTheRareMissingStratum(testCase)
%TESTSTRATIFIEDDRAWPRESERVESTHERARE... "(missing)" is a stratum, not an absence.
%
% One recording has no genotype. Proportional allocation over a request of four
% gives it 0.33 of a place and rounds it away; the floor puts it back. That is
% the whole point of representing missing metadata rather than dropping it.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
resolved = vawlume.eda.resolveStrata(conn, 1:12);
subset = vawlume.eda.sampleRecordings(resolved, Seed=11, Size=4);

allocation = subset.allocation;
verifyEqual(testCase, sort(allocation.stratum_value), ...
    sort(["(missing)"; "KO"; "WT"]));
missingRow = allocation(allocation.stratum_value == "(missing)", :);
verifyEqual(testCase, missingRow.largest_remainder_count, 0);
verifyEqual(testCase, missingRow.floor_added, 1);
verifyEqual(testCase, missingRow.realized_count, 1);

verifyTrue(testCase, subset.rare_stratum_effect.floor_changed_allocation);
verifyEqual(testCase, subset.rare_stratum_effect.strata_raised_by_floor, ...
    "(missing)");
verifyEqual(testCase, subset.rare_stratum_effect.places_added_by_floor, 1);
verifyEqual(testCase, subset.rare_stratum_effect.places_removed_by_trimming, 1);

verifyEqual(testCase, sum(allocation.realized_count), 4);
verifyEqual(testCase, subset.realized_size, 4);
verifyTrue(testCase, ismember(12, subset.selected_recording_ids));
end

% ---------------------------------------------------------------- tripwire ---

function testNothingInThisPartWritesToTheDatabase(testCase)
%TESTNOTHINGINTHISPARTWRITES... Part 9 chooses recordings; it stores nothing.
%
% Also the support-pattern tripwire. Sampling may not read an output of the
% analysis the subset exists to probe, so these two functions must not touch the
% agreement, matching, or consilience tables at all - the grammar's refusal
% covers the configured path, and this covers the implementation.
files = ["resolveStrata.m", "sampleRecordings.m"];
forbiddenWrites = ["INSERT INTO", "UPDATE ", "DELETE FROM", "CREATE TABLE", ...
    "DROP "];
forbiddenReads = ["supported_extractor_pair_pattern", "extractor_set_key", ...
    "agreement_groups", "candidate_pairs", "consilience", ...
    "matching_analyses", "FROM v_recording_entity_context"];
forbiddenFigures = ["figure(", "plot(", "histogram(", "bar("];

for name = files
    % Comment lines are stripped first. Both functions name the forbidden
    % tables in prose - saying WHY a stratum may not be an analysis output is
    % most of what keeps the rule alive - and a scan that could not tell a
    % docstring from a query would force that explanation out of the code.
    source = codeOnly(fileread(fullfile(repoRootPath(), "src", "+vawlume", ...
        "+eda", name)));
    for token = [forbiddenWrites, forbiddenReads, forbiddenFigures]
        verifyEqual(testCase, numel(strfind(source, token)), 0, ...
            name + " contains '" + token + "'.");
    end
end

% And the observable version: a full resolve-and-sample changes no row count.
[conn, cleanup] = setUpFixture(); %#ok<ASGLU>
before = tableCounts(conn);
resolved = vawlume.eda.resolveStrata(conn, 1:12);
vawlume.eda.sampleRecordings(resolved, Seed=3);
verifyEqual(testCase, tableCounts(conn), before);
end

% ---------------------------------------------------------------- helpers ---

function value = codeOnly(source)
lines = splitlines(string(source));
value = strjoin(lines(~startsWith(strtrim(lines), "%")), newline);
end

function value = stratumOf(resolved, field, recordingId)
selected = resolved.strata(resolved.strata.field == field & ...
    resolved.strata.recording_id == recordingId, :);
value = selected.stratum_value;
end

function value = reasonFor(considered, field)
value = considered.rejection_reason(considered.field == field);
end

function verifySubstring(testCase, haystack, needle)
verifyTrue(testCase, contains(string(haystack), needle), ...
    "Expected '" + needle + "' in: " + string(haystack));
end

function counts = tableCounts(conn)
names = ["recordings", "recording_attributes", "entity_attributes", ...
    "recording_entity_links", "recording_epochs", "experimental_entities"];
counts = zeros(numel(names), 1);
for index = 1:numel(names)
    rows = fetch(conn, "SELECT COUNT(*) AS n FROM " + names(index));
    counts(index) = double(rows.n(1));
end
end

% ---------------------------------------------------------------- fixture ---

function [conn, cleanup] = setUpFixture()
%SETUPFIXTURE Twelve recordings carrying every metadata shape the grammar reads.
%
% Deliberately built rather than borrowed from the phase-1 fixture, which has two
% recordings - too few for a coverage fraction, a dominant stratum, or an
% allocation to mean anything. The shapes here are the ones that matter:
%
%   genotype   WT x6, KO x5, one recording with no row  -> qualifies, 0.50
%   phase      early x7, late x5                        -> qualifies, 0.58
%   strain     B6 x10, CD1 x1, one unlinked recording   -> qualifies, 0.83
%   cohort     one value on all twelve                  -> one distinct value
%   rig        present on six of twelve                 -> coverage 0.50
%   sex        REC_01 links a male AND a female         -> not unique
%   batch      integer-typed, eleven of twelve share a value  -> dominance 0.92
%   is_pilot   boolean-typed, eleven of twelve share a value  -> dominance 0.92
%
% REC_12 has no `recording_entity_links` row at all. That single recording is
% what separates a LEFT JOIN from the convenient view.
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
conn = sqlite(char(fullfile(scratch, "strata.sqlite")), "create");
vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
cleanup = onCleanup(@() tearDown(conn, scratch));

execute(conn, "INSERT INTO projects(project_key,project_name) " + ...
    "VALUES('strata-project','Strata Project')");
execute(conn, "INSERT INTO entity_types(project_id,native_name," + ...
    "is_biological_unit,is_subject_like) VALUES(1,'animal',1,1)");

genotype = ["WT" "WT" "WT" "WT" "WT" "WT" "KO" "KO" "KO" "KO" "KO" ""];
rig = ["RIG_A" "RIG_A" "RIG_A" "RIG_A" "RIG_B" "RIG_B" "" "" "" "" "" ""];
phase = ["early" "early" "early" "early" "late" "late" "late" "late" ...
    "late" "early" "early" "early"];
strain = ["B6" "B6" "B6" "B6" "B6" "B6" "B6" "B6" "B6" "CD1" "B6" ""];

for index = 1:12
    native = sprintf("REC_%02d", index);
    execute(conn, "INSERT INTO source_files(project_id,file_role," + ...
        "path_or_uri,relative_path,filename) VALUES(1,'recording_audio'," + ...
        "'audio/" + native + ".wav','audio/" + native + ".wav','" + ...
        native + ".wav')");
    execute(conn, "INSERT INTO recordings(project_id,source_file_id," + ...
        "native_recording_id) VALUES(1," + index + ",'" + native + "')");

    insertText(conn, index, "cohort", "C1");
    if strlength(genotype(index)) > 0
        insertText(conn, index, "genotype", genotype(index));
    end
    if strlength(rig(index)) > 0
        insertText(conn, index, "rig", rig(index));
    end
    execute(conn, "INSERT INTO recording_attributes(recording_id," + ...
        "attribute_name,value_type,value_integer) VALUES(" + index + ...
        ",'batch','integer'," + (1 + (index == 12)) + ")");
    execute(conn, "INSERT INTO recording_attributes(recording_id," + ...
        "attribute_name,value_type,value_boolean) VALUES(" + index + ...
        ",'is_pilot','boolean'," + double(index == 1) + ")");
    execute(conn, "INSERT INTO recording_epochs(recording_id,epoch_name," + ...
        "epoch_type,start_time_s,end_time_s) VALUES(" + index + ",'" + ...
        phase(index) + "','phase',0,10)");

    if strlength(strain(index)) == 0
        continue
    end
    entityId = index + 1;
    execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
        "entity_type_id,native_id) VALUES(" + entityId + ",1,1,'ANIMAL_" + ...
        index + "')");
    execute(conn, "INSERT INTO entity_attributes(entity_id,attribute_name," + ...
        "value_type,value_text) VALUES(" + entityId + ",'strain','text','" + ...
        strain(index) + "')");
    execute(conn, "INSERT INTO entity_attributes(entity_id,attribute_name," + ...
        "value_type,value_text) VALUES(" + entityId + ",'sex','text','male')");
    execute(conn, "INSERT INTO recording_entity_links(recording_id," + ...
        "entity_id,link_type,role_label) VALUES(" + index + "," + entityId + ...
        ",'participant','subject')");
end

% REC_01 is a dyad: a second animal, same strain, opposite sex. `sex` is then
% multi-valued for one recording and `strain` is not, which is what separates
% "the recording has two entities" from "the field disagrees".
execute(conn, "INSERT INTO experimental_entities(entity_id,project_id," + ...
    "entity_type_id,native_id) VALUES(100,1,1,'ANIMAL_1_PARTNER')");
execute(conn, "INSERT INTO entity_attributes(entity_id,attribute_name," + ...
    "value_type,value_text) VALUES(100,'strain','text','B6')");
execute(conn, "INSERT INTO entity_attributes(entity_id,attribute_name," + ...
    "value_type,value_text) VALUES(100,'sex','text','female')");
execute(conn, "INSERT INTO recording_entity_links(recording_id,entity_id," + ...
    "link_type,role_label) VALUES(1,100,'participant','partner')");
end

function insertText(conn, recordingId, name, value)
execute(conn, "INSERT INTO recording_attributes(recording_id," + ...
    "attribute_name,value_type,value_text) VALUES(" + recordingId + ",'" + ...
    name + "','text','" + value + "')");
end

function tearDown(conn, scratch)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
end

function value = repoRootPath()
value = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
