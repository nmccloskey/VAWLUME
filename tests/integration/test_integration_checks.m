function tests = test_integration_checks
%TEST_INTEGRATION_CHECKS Plan §12's integration checks that need a database (7.13).
%
% Contract 07 D13's guards E7, E8, E10, E12 and E13, plus the alignment-intake
% invariants on the integrated fixture. The static guards live in
% tests/unit/test_package_boundaries.m (E11, invariant 54) and
% tests/integration/test_localization_evidence.m (E9); E14 extends
% tests/unit/test_seed_registration.m.
%
% One fixture is built for the suite. Its native tables and per-table row counts
% are captured BEFORE anything else runs, then the read and export pipeline is
% applied: every compare path pair, report, the QC facts, the CSV export, and
% the exploration's diagnostics. E8 then compares the native tables again.
% (7.8's and 7.9's sensitivity runs are covered by the same comparison inside
% their own suites, which already apply them.)
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(root, "src"));
[fixture, cleanup] = vawlume.db.buildIntegratedFixture(RepoRoot=root);
work = string(tempname);
mkdir(work);
t = struct(root=root, fixture=fixture, cleanup=cleanup, work=work);
t.counts_built = rowCounts(fixture.conn);
t.native_before = nativeSnapshot(fixture.conn);

% The pipeline. Refusals by name are part of the contract (different event sets
% need a correspondence analysis) and are kept, not swallowed silently.
runs = string(fieldnames(fixture.manifest.runs))';
t.compare_outcomes = strings(0, 1);
for left = runs
    for right = runs(runs ~= left)
        try
            vawlume.attribution.compare(fixture.conn, ...
                struct(attribution_run_id=fixture.manifest.runs.(left).attribution_run_id), ...
                struct(attribution_run_id=fixture.manifest.runs.(right).attribution_run_id));
            t.compare_outcomes(end + 1, 1) = left + "/" + right + ": compared";
        catch exception
            t.compare_outcomes(end + 1, 1) = left + "/" + right + ": " + exception.identifier;
        end
    end
    vawlume.attribution.report(fixture.conn, ...
        struct(attribution_run_id=fixture.manifest.runs.(left).attribution_run_id));
end
for native = ["native_detections", "native_consensus"]
    vawlume.estimator.qcFacts(fixture.conn, ...
        struct(attribution_run_id=fixture.manifest.runs.(native).attribution_run_id));
end
t.export_dir = fullfile(work, "export");
t.export = vawlume.export.database(fixture.database_path, Output=t.export_dir);
% What the export must equal, read from SQLite at the moment it was exported
% (the exploration below adds analysis rows afterwards).
t.at_export = databaseState(fixture.conn);
t.schema_only_dir = fullfile(work, "schema_only");
t.schema_only = vawlume.export.database(Output=t.schema_only_dir, SchemaOnly=true);
t.exploration = vawlume.eda.runExploration(fixture.conn, ...
    struct(project_key=fixture.manifest.project_key), Stages="diagnostics", ...
    RepoRoot=root, OutputRoot=fullfile(work, "exploration"), Print=false);
t.native_after = nativeSnapshot(fixture.conn);
testCase.TestData = t;
end

function teardownOnce(testCase)
testCase.TestData.cleanup = [];
if isfolder(testCase.TestData.work)
    rmdir(testCase.TestData.work, "s");
end
end

% ------------------------------------------------------ check 1: provenance (E7) ---

function testRealShapeTokensTraceToTheTargetsTheyReach(testCase)
% A token is stored raw with no numeric payload (test_integrated_fixture), and
% it stays readable along the path its detection takes. MUPET's terminal "_"
% detection is a member of a consensus event that the native consensus run
% targets: from that target, the raw token and its absent payload are read back
% through stored rows only. USVSEG's "NaN" detection reaches matching and
% agreement; no attribution run in the fixture targets an event set holding it
% (recorded at 7.13), so its trace ends at the agreement group.
f = testCase.TestData.fixture;
t = f.manifest.real_shape_tokens;

mupet = fetch(f.conn, "SELECT at.attribution_target_id, " + ...
    "IFNULL(em.native_raw_token,'<NULL>') AS raw, " + ...
    "em.native_value_real IS NULL AS no_native, " + ...
    "em.canonical_value_real IS NULL AS no_canonical " + ...
    "FROM attribution_targets at " + ...
    "JOIN consensus_event_members cem ON cem.consensus_event_id = at.consensus_event_id " + ...
    "JOIN event_measurements em ON em.detection_id = cem.detection_id " + ...
    "WHERE cem.detection_id = " + string(t.mupet_terminal_interval.detection_id) + ...
    " AND em.native_raw_token = '_'");
verifyNotEmpty(testCase, mupet, "MUPET's '_' does not reach an attribution target.");
verifyEqual(testCase, unique(string(mupet.raw)), "_");
verifyTrue(testCase, all(logical(mupet.no_native)), "'_' carries a native number.");
verifyTrue(testCase, all(logical(mupet.no_canonical)), "'_' carries a canonical number.");

usvseg = fetch(f.conn, "SELECT agm.agreement_group_id, " + ...
    "em.native_value_real IS NULL AS no_native, " + ...
    "em.canonical_value_real IS NULL AS no_canonical, " + ...
    "(SELECT COUNT(*) FROM match_group_members mgm " + ...
    " WHERE mgm.detection_id = em.detection_id) AS match_groups " + ...
    "FROM agreement_group_members agm " + ...
    "JOIN event_measurements em ON em.detection_id = agm.detection_id " + ...
    "WHERE agm.detection_id = " + string(t.usvseg_nan.detection_id) + ...
    " AND em.native_raw_token = 'NaN'");
verifyNotEmpty(testCase, usvseg, "USVSEG's 'NaN' does not reach agreement.");
verifyGreaterThan(testCase, double(usvseg.match_groups(1)), 0);
verifyTrue(testCase, all(logical(usvseg.no_native)), "'NaN' carries a native number.");
verifyTrue(testCase, all(logical(usvseg.no_canonical)), "'NaN' carries a canonical number.");
end

% ---------------------------------------- check 2: native never overwritten (E8) ---

function testNativeTablesAreUnchangedByThePipeline(testCase)
t = testCase.TestData;
names = string(fieldnames(t.native_before))';
populated = names(arrayfun(@(n) height(t.native_before.(n)) > 0, names));
verifyTrue(testCase, all(ismember(["detections", "event_measurements", ...
    "imported_attribution_claims", "tracking_series", "artifacts"], populated)), ...
    "A native table the guard depends on is empty, so it would compare nothing.");
for name = names
    before = t.native_before.(name);
    after = t.native_after.(name);
    verifyGreaterThanOrEqual(testCase, height(after), height(before), ...
        "Native rows of " + name + " were deleted under the pipeline.");
    verifyEqual(testCase, after(1:min(end, height(before)), :), before, ...
        "Native rows of " + name + " were overwritten under the pipeline.");
end
% The pipeline did run: comparisons and refusals were both exercised.
verifyTrue(testCase, any(endsWith(t.compare_outcomes, ": compared")));
verifyEqual(testCase, t.exploration.stages.status(t.exploration.stages.stage == ...
    "diagnostics"), "completed");
end

% -------------------------------- check 3: one transform representation (storage) ---

function testEveryStoredTransformHasOneRepresentation(testCase)
% The static scanner (E9) keeps transform arithmetic in +alignment/. In storage,
% every fitted transform is a time_alignment_runs row with its segments, and
% every native run that used one cites it: a native evidence row that names an
% alignment run names one that exists.
conn = testCase.TestData.fixture.conn;
orphans = fetch(conn, "SELECT COUNT(*) AS n FROM attribution_evidence ae " + ...
    "WHERE ae.alignment_run_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM " + ...
    "time_alignment_runs r WHERE r.alignment_run_id = ae.alignment_run_id)");
verifyEqual(testCase, double(orphans.n(1)), 0);
cited = fetch(conn, "SELECT COUNT(*) AS n FROM attribution_evidence " + ...
    "WHERE alignment_run_id IS NOT NULL");
verifyGreaterThan(testCase, double(cited.n(1)), 0, ...
    "No evidence row cites an alignment run, so the citation is not exercised.");
unsegmented = fetch(conn, "SELECT COUNT(*) AS n FROM time_alignment_runs r " + ...
    "WHERE r.status NOT IN ('registered','rejected','failed') AND NOT EXISTS " + ...
    "(SELECT 1 FROM alignment_segments s WHERE s.alignment_run_id = r.alignment_run_id)");
verifyEqual(testCase, double(unsegmented.n(1)), 0, ...
    "A solved transform has no segment row: its coefficients live elsewhere.");
end

% ------------------------------------------- check 4: no dense duplication (E10) ---

function testDoublingTheDenseInputsChangesNoRowCount(testCase)
% Contract 07 D13: doubling the fixture's tracking samples and audio length
% changes no row count in any table. The doubled fixture is built by a scratch
% copy of the builder that differs only in its session duration (200 -> 400 s)
% and tracking frame rate (30 -> 60 frames/s): test-time code, so no production
% option exists for it.
t = testCase.TestData;
builder = fullfile(t.root, "src", "+vawlume", "+db", "buildIntegratedFixture.m");
text = string(fileread(builder));
doubled = replace(text, "function [fixture, cleanup] = buildIntegratedFixture(", ...
    "function [fixture, cleanup] = buildDoubledIntegratedFixture(");
doubled = replace(doubled, "g.duration_s = 200;", "g.duration_s = 400;");
doubled = replace(doubled, "frames = (ceil(window(1) * 30):floor(window(2) * 30))' / 30;", ...
    "frames = (ceil(window(1) * 60):floor(window(2) * 60))' / 60;");
verifyEqual(testCase, count(doubled, "400;") - count(text, "400;"), 1, ...
    "The duration line moved; the doubled builder is no longer doubled.");
verifyEqual(testCase, count(doubled, "* 60)") - count(text, "* 60)"), 2, ...
    "The tracking frame-rate line moved; the doubled builder is no longer doubled.");
folder = fullfile(t.work, "doubled_builder");
mkdir(folder);
writelines(doubled, fullfile(folder, "buildDoubledIntegratedFixture.m"));
addpath(folder);
removePath = onCleanup(@() rmpath(folder));
[big, cleanupBig] = buildDoubledIntegratedFixture(RepoRoot=t.root, ...
    Root=fullfile(t.work, "doubled")); %#ok<ASGLU>

% The dense inputs really are about twice as large.
[normalTracking, normalAudio] = denseSizes(t.fixture);
[bigTracking, bigAudio] = denseSizes(big);
verifyGreaterThan(testCase, bigTracking, 1.8 * normalTracking);
verifyGreaterThan(testCase, bigAudio, 1.8 * normalAudio);

counts = rowCounts(big.conn);
names = string(fieldnames(t.counts_built))';
changed = names(arrayfun(@(n) counts.(n) ~= t.counts_built.(n), names));
verifyEmpty(testCase, changed, "Row counts that grew with the dense inputs: " + ...
    strjoin(changed + " " + arrayfun(@(n) string(t.counts_built.(n)), changed) + ...
    "->" + arrayfun(@(n) string(counts.(n)), changed), ", "));
end

% ----------------------------- cross-workstream: CSV export of the database (E12) ---

function testTheIntegratedDatabaseExportsFaithfully(testCase)
t = testCase.TestData;
state = t.at_export;
tables = string(fieldnames(state.counts));
verifyGreaterThan(testCase, numel(tables), 50);
for name = tables'
    path = fullfile(t.export_dir, "csv", name + ".csv");
    verifyTrue(testCase, isfile(path), name + " was not exported.");
    if ~isfile(path)
        continue
    end
    csv = readCsv(path);
    verifyEqual(testCase, csv.header, state.columns.(name), ...
        name + ": header differs from pragma_table_info.");
    verifyEqual(testCase, numel(csv.rows), state.counts.(name), ...
        name + ": row count differs from SQLite.");
    if isfield(state.cells, name) && ~isempty(csv.rows)
        expected = state.cells.(name);
        for r = 1:numel(csv.rows)
            verifyEqual(testCase, csv.rows{r}, expected(r, :), ...
                name + " row " + r + ": a cell differs from SQLite.");
        end
    end
end
% The non-ASCII and newline value 7.3 put in the project description.
description = t.fixture.manifest.csv_values.project_description;
verifyTrue(testCase, contains(description, char(8212)) && contains(description, newline));
projects = readCsv(fullfile(t.export_dir, "csv", "projects.csv"));
column = projects.header == "description";
verifyEqual(testCase, projects.rows{1}(column), description);
end

function testTheSchemaOnlyExportAndTheMetadataAreComplete(testCase)
t = testCase.TestData;
verifyTrue(testCase, isfile(fullfile(t.schema_only_dir, "meta", "columns.csv")));
verifyFalse(testCase, isfolder(fullfile(t.schema_only_dir, "csv")), ...
    "A schema-only export wrote data files.");
version = fetch(t.fixture.conn, "SELECT schema_version FROM schema_info");
verifyEqual(testCase, string(version.schema_version(1)), "0.14-draft");
report = vawlume.schema.validateMetadata(Mode="complete", RepoRoot=t.root, Print=false);
verifyTrue(testCase, report.passed, "Schema metadata is not complete.");
verifyEqual(testCase, string(report.schema_version), "0.14-draft");
end

% ---------------------- cross-workstream: exploration over the integrated fixture (E13) ---

function testTheExplorationDiagnosticsRunWithoutAFabricatedExtent(testCase)
% Diagnostics run over the integrated fixture (bounded: no design, no probe).
% USVSEG reports no band edges, so on every candidate row of a USVSEG pair the
% band-edge discrepancies have no value and are counted not_eligible: nothing
% fills them in from another extractor or from call geometry.
r = testCase.TestData.exploration;
ran = r.stages(ismember(r.stages.stage, ["dataset", "reference", "diagnostics"]), :);
verifyTrue(testCase, all(ran.status == "completed"));
surface = r.diagnostics.surface;
usvseg = contains(surface.metrics.extractor_pair_key, "usvseg");
verifyGreaterThan(testCase, nnz(usvseg), 0, "No USVSEG candidate row to check.");
for class = ["frequency_min", "frequency_max", "frequency_bandwidth"]
    name = "discrepancy_vocalization_" + class;
    verifyFalse(testCase, any(isfinite(surface.metrics.(name)(usvseg))), ...
        name + " has a value on a USVSEG row: an extent was fabricated.");
    coverage = surface.coverage(surface.coverage.metric_name == name, :);
    verifyGreaterThan(testCase, coverage.not_eligible, 0, ...
        name + ": no row is counted not_eligible.");
    verifyEqual(testCase, coverage.supported, ...
        nnz(isfinite(surface.metrics.(name))), ...
        name + ": coverage claims support the values do not have.");
end
end

% ------------------------------- cross-workstream: alignment-intake invariants ---

function testNonNativeClocksAreRecordingScopedOnTheFixture(testCase)
% The 2026-09-29 intake fix, on the integrated fixture's own manifests: every
% timebase belongs to one recording, so a same-name clock in two recordings
% stays two timebases. (Changed stream evidence and the onset rule are refused
% by test_alignment_intake and test_external_alignment_source_mapping.)
%
% Scope is the manifest's to declare: the fixture declares exactly one clock,
% the neural reference, with scope="project" (buildIntegratedFixture's
% alignment manifest). Every other timebase, the non-native video clock among
% them, took the default and must be recording-scoped.
conn = testCase.TestData.fixture.conn;
rows = fetch(conn, "SELECT timebase_name, recording_id IS NULL AS unscoped, " + ...
    "is_recording_native FROM timebases");
verifyGreaterThan(testCase, nnz(~logical(rows.is_recording_native)), 1, ...
    "Fewer than two non-native clocks: the default is not exercised.");
unscoped = string(rows.timebase_name(logical(rows.unscoped)));
verifyEqual(testCase, unscoped, "neural_native", ...
    "Only the clock the manifest declared project-scoped may lack a recording.");
end

% ---------------------------------------------------------------- helpers ---

function value = nativeTables()
value = ["detections", "event_measurements", "external_events", ...
    "external_streams", "external_stream_sources", "external_stream_coverage", ...
    "tracking_streams", "tracking_series", "tracking_identity_associations", ...
    "imported_attribution_windows", "imported_attribution_claims", ...
    "attribution_localization_estimates", "artifacts", "source_files", ...
    "alignment_anchor_observations", "extraction_runs"];
end

function snapshot = nativeSnapshot(conn)
% Every column, type-faithful (real values bit-exact), in rowid order.
snapshot = struct();
for name = nativeTables()
    columns = string(fetch(conn, "SELECT name FROM pragma_table_info('" + name + ...
        "')").name)';
    snapshot.(name) = expectedCells(conn, name, columns);
end
end

function cells = expectedCells(conn, name, columns)
% The export contract's representation, written independently: 'V' + text
% (REAL by printf %!.17g, BLOB as hex) or 'N' for NULL, decoded to a string
% matrix with <missing> for NULL.
projections = "IFNULL('V' || CASE typeof(""" + columns + """) " + ...
    "WHEN 'real' THEN printf('%!.17g', """ + columns + """) " + ...
    "WHEN 'blob' THEN hex(""" + columns + """) " + ...
    "ELSE CAST(""" + columns + """ AS TEXT) END, 'N')";
rows = fetch(conn, "SELECT " + strjoin(projections + " AS c" + (1:numel(columns)), ", ") + ...
    " FROM """ + name + """ ORDER BY rowid");
cells = strings(height(rows), numel(columns));
for k = 1:numel(columns)
    raw = string(rows{:, k});
    present = startsWith(raw, "V");
    cells(present, k) = extractAfter(raw(present), 1);
    cells(~present, k) = nullToken();
end
end

function value = nullToken()
% SQL NULL in these string matrices: a token no exported value can collide with
% here, so verifyEqual compares NULL to NULL (it never equates two <missing>).
value = "<<NULL>>";
end

function state = databaseState(conn)
% Per table: its columns (pragma_table_info, in order) and row count; and, for
% the attribution tables and projects, every cell as the export must write it.
state = struct(counts=rowCounts(conn), columns=struct(), cells=struct());
for name = string(fieldnames(state.counts))'
    columns = string(fetch(conn, "SELECT name FROM pragma_table_info('" + name + ...
        "')").name)';
    state.columns.(name) = columns;
    if startsWith(name, ["attribution_", "imported_attribution_"]) || name == "projects"
        state.cells.(name) = expectedCells(conn, name, columns);
    end
end
end

function counts = rowCounts(conn)
counts = struct();
tables = string(fetch(conn, "SELECT name FROM sqlite_master WHERE type='table' " + ...
    "AND name NOT LIKE 'sqlite_%'").name)';
for name = tables
    n = fetch(conn, "SELECT COUNT(*) AS n FROM """ + name + """");
    counts.(name) = double(n.n(1));
end
end

function [tracking, audio] = denseSizes(fixture)
files = string({dir(fullfile(fixture.root, "**", "*.csv")).folder}) + filesep + ...
    string({dir(fullfile(fixture.root, "**", "*.csv")).name});
tracking = 0;
for file = files
    header = strtrim(string(splitlines(fileread(file))));
    if startsWith(header(1), "time_s,subject,bodypart")
        tracking = tracking + nnz(strlength(header) > 0) - 1;
    end
end
wavs = dir(fullfile(fixture.root, "**", "*.wav"));
audio = 0;
for k = 1:numel(wavs)
    info = audioinfo(fullfile(wavs(k).folder, wavs(k).name));
    audio = audio + info.TotalSamples;
end
end

function csv = readCsv(path)
% RFC 4180 with CRLF records, as the export writes it: every non-NULL value is
% quoted, so a bare empty field is NULL.
fid = fopen(path, "r");
bytes = fread(fid, Inf, "*uint8")';
fclose(fid);
text = string(native2unicode(bytes, "UTF-8"));
tokens = regexp(text, '("(?:[^"]|"")*"|[^,"\r\n]*)(,|\r\n)', "tokens");
records = {};
values = strings(1, 0);
for k = 1:numel(tokens)
    field = string(tokens{k}{1});
    if startsWith(field, '"')
        field = replace(extractBetween(field, 2, strlength(field) - 1), '""', '"');
    elseif strlength(field) == 0
        field = nullToken();
    end
    values(end + 1) = field; %#ok<AGROW>
    if string(tokens{k}{2}) == sprintf("\r\n")
        records{end + 1} = values; %#ok<AGROW>
        values = strings(1, 0);
    end
end
csv = struct(header=records{1}, rows={records(2:end)});
end
