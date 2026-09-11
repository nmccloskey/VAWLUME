function tests = test_tracking_source_mapping
%TEST_TRACKING_SOURCE_MAPPING Profile validation and database-free tracking IR.
%
% The claims this suite holds:
%
%   the tracking contract names roles, never vendor columns;
%   the IR carries stream, series and column metadata - never a sample;
%   identity loss is an error, not a silent merge;
%   a frame-only basis without a frame rate is refused;
%   +source_mapping stays database-free.
tests = functiontests(localfunctions);
end

% ------------------------------------------------------- profile validation ---

function testShippedTrackingProfileValidates(testCase)
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
cleanup = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

loaded = vawlume.source_mapping.loadProfile(profilePath(repoRoot), ...
    RepoRoot=repoRoot);
verifyTrue(testCase, loaded.report.is_valid);
verifyEqual(testCase, loaded.report.error_count, 0);
verifyEqual(testCase, loaded.profile_kinds, "tracking_input_mapping");
verifyEqual(testCase, loaded.profile_schema_versions, "0.3-draft");
verifyEqual(testCase, loaded.profile_version_labels, "0.1.0");
verifyEmpty(testCase, loaded.warnings);

clear cleanup
end

function testMissingRolesAndBadBasisAreRefused(testCase)
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
cleanup = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

% Position is the irreducible content of a tracking row.
report = validateVariant(repoRoot, @(d) removeColumn(d, "position_y"));
verifyFalse(testCase, report.is_valid);
verifyTrue(testCase, any(report.issue_table.code == "PROFILE_MISSING_FIELD"));

% Identity is what makes a sample attributable to a trace.
report = validateVariant(repoRoot, @(d) removeColumn(d, "bodypart_label"));
verifyFalse(testCase, report.is_valid);

% A frame index relates to no clock without a rate.
report = validateVariant(repoRoot, @(d) frameOnlyWithoutRate(d));
verifyFalse(testCase, report.is_valid);
verifyTrue(testCase, any(contains(report.issue_table.message, ...
    "nominal_frame_rate_hz")));

% The basis vocabulary is closed; an unfamiliar value is a typo, not a concept.
report = validateVariant(repoRoot, @(d) setBasis(d, "sample_index"));
verifyFalse(testCase, report.is_valid);

% A canonical role declared twice for one native label is ambiguous.
report = validateVariant(repoRoot, @(d) duplicateBodypartRole(d));
verifyFalse(testCase, report.is_valid);

clear cleanup
end

% -------------------------------------------------------------------- the IR ---

function testIRCarriesMetadataAndNeverASample(testCase)
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
cleanup = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

tbl = syntheticTrackingTable();
ir = vawlume.source_mapping.mapTableToIR(tbl, profilePath(repoRoot), ...
    RepoRoot=repoRoot, RelativePath="synthetic/tracking/session_01.csv");

verifyTrue(testCase, ir.valid_for_ingest);

% 24 samples in, one stream and four traces out. The IR summarizes; it never
% mirrors the artifact.
verifyEqual(testCase, height(tbl), 24);
verifyEqual(testCase, height(ir.tracking_streams), 1);
verifyEqual(testCase, height(ir.tracking_series), 4);
verifyEqual(testCase, ir.summary.tracking_series_count, 4);

% No per-sample row reached any IR table.
verifyEqual(testCase, height(ir.events), 0);
verifyEqual(testCase, height(ir.values), 0);
verifyEqual(testCase, height(ir.records), 0);

stream = table2struct(ir.tracking_streams(1, :));
verifyEqual(testCase, stream.stream_key, "tracking_primary");
verifyEqual(testCase, stream.coordinate_system_key, "arena_2d");
verifyEqual(testCase, stream.native_time_basis, "time");
verifyEqual(testCase, stream.declared_sample_count, 24);
verifyEqual(testCase, stream.has_confidence, 1);

% Series are the distinct (entity, bodypart) traces, with native labels kept.
verifyEqual(testCase, sort(ir.tracking_series.native_entity_label), ...
    ["mouse_a"; "mouse_a"; "mouse_b"; "mouse_b"]);
verifyEqual(testCase, sort(unique(ir.tracking_series.native_bodypart_label)), ...
    ["snout"; "tail_base"]);
verifyEqual(testCase, sum(ir.tracking_series.sample_count), height(tbl));

% The canonical role is additive: declared for snout, absent for tail_base,
% and the native label survives in both cases.
snout = ir.tracking_series(ir.tracking_series.native_bodypart_label == "snout", :);
tail = ir.tracking_series(ir.tracking_series.native_bodypart_label == "tail_base", :);
verifyEqual(testCase, unique(snout.canonical_bodypart_role), "snout");
verifyEqual(testCase, unique(tail.canonical_bodypart_role), "");

% The column contract records every role, including the ones not supplied.
roles = ir.tracking_columns.role;
verifyTrue(testCase, all(ismember(["position_x", "position_y", "entity_label", ...
    "bodypart_label", "native_time", "confidence"], roles)));
absent = ir.tracking_columns(ir.tracking_columns.role == "position_z", :);
verifyEqual(testCase, absent.status, "absent");

% Coverage is the artifact's own observed span, as one segment.
verifyEqual(testCase, height(ir.coverage), 1);
verifyEqual(testCase, double(ir.coverage.start_time_native(1)), 0);
verifyEqual(testCase, double(ir.coverage.end_time_native(1)), 5, AbsTol=1e-12);

clear cleanup
end

function testUnlabelledRowsAreAnErrorNotASilentMerge(testCase)
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
cleanup = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

tbl = syntheticTrackingTable();
tbl.bodypart(3) = "";

ir = vawlume.source_mapping.mapTableToIR(tbl, profilePath(repoRoot), ...
    RepoRoot=repoRoot);

% Assigning an unlabelled sample to a default trace would invent identity the
% source did not supply, so the mapping is invalid instead.
verifyFalse(testCase, ir.valid_for_ingest);
verifyTrue(testCase, any(ir.issues.code == "TRACKING_IDENTITY_MISSING"));

clear cleanup
end

function testDeclaredColumnThatIsAbsentFromTheTableIsRefused(testCase)
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
cleanup = onCleanup(@() rmpath(fullfile(repoRoot, "src")));

tbl = removevars(syntheticTrackingTable(), "y");
ir = vawlume.source_mapping.mapTableToIR(tbl, profilePath(repoRoot), ...
    RepoRoot=repoRoot);

verifyFalse(testCase, ir.valid_for_ingest);
row = ir.tracking_columns(ir.tracking_columns.role == "position_y", :);
verifyEqual(testCase, row.status, "invalid");

clear cleanup
end

function testSourceMappingRemainsDatabaseFree(testCase)
% The Phase 7 invariant holds through tracking: mapping never touches SQLite.
repoRoot = repoRootPath();
files = dir(fullfile(repoRoot, "src", "+vawlume", "+source_mapping", "**", "*.m"));
forbidden = ["sqlwrite(", "sqlite(", "execute(", "fetch(", "commit(", "rollback("];
for index = 1:numel(files)
    source = string(fileread(fullfile(files(index).folder, files(index).name)));
    for token = forbidden
        verifyFalse(testCase, contains(source, token), ...
            files(index).name + " must not call " + token);
    end
end
end

% ------------------------------------------------------------------ helpers ---

function value = profilePath(repoRoot)
value = fullfile(repoRoot, "config", "01_mapping_profiles", "tracking", ...
    "generic_tracking_mapping_profile.json");
end

function report = validateVariant(repoRoot, mutate)
document = jsondecode(fileread(profilePath(repoRoot)));
document.profiles = mutate(document.profiles);
report = vawlume.source_mapping.validateProfile(document);
end

function profiles = removeColumn(profiles, name)
profiles.columns = rmfield(profiles.columns, name);
end

function profiles = frameOnlyWithoutRate(profiles)
profiles.context.native_time_basis = "frame";
profiles.columns.native_frame = struct(source_field="frame");
end

function profiles = setBasis(profiles, basis)
profiles.context.native_time_basis = basis;
end

function profiles = duplicateBodypartRole(profiles)
profiles.bodypart_roles = [ ...
    struct(native_bodypart_label="snout", canonical_bodypart_role="snout"); ...
    struct(native_bodypart_label="snout", canonical_bodypart_role="head")];
end

function tbl = syntheticTrackingTable()
%SYNTHETICTRACKINGTABLE Long-form: one row per (time, entity, bodypart).
%
% Six timestamps, two subjects, two landmarks. Small enough to read, large
% enough that a per-sample IR row would be obvious.
times = (0:5)';
subjects = ["mouse_a", "mouse_b"];
parts = ["snout", "tail_base"];

timeColumn = [];
subjectColumn = strings(0, 1);
partColumn = strings(0, 1);
for subjectIndex = 1:numel(subjects)
    for partIndex = 1:numel(parts)
        timeColumn = [timeColumn; times]; %#ok<AGROW>
        subjectColumn = [subjectColumn; repmat(subjects(subjectIndex), 6, 1)]; %#ok<AGROW>
        partColumn = [partColumn; repmat(parts(partIndex), 6, 1)]; %#ok<AGROW>
    end
end

count = numel(timeColumn);
tbl = table(timeColumn, subjectColumn, partColumn, ...
    (1:count)' * 0.5, (1:count)' * 0.25, repmat(0.97, count, 1), ...
    VariableNames=["time_s", "subject", "bodypart", "x", "y", "likelihood"]);
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

