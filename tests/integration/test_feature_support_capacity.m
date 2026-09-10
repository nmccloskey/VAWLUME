function tests = test_feature_support_capacity
%TEST_FEATURE_SUPPORT_CAPACITY Potential feature support is a query, not a column.
%
% How much cross-extractor feature support is available for a comparison is not
% a property of a native feature. It depends on which extractor versions are
% being compared, on the exact registered relationships between their features,
% on consilience_eligible, on equivalence class and operational variant, on unit
% compatibility, and on the versioned comparison policy that says which classes
% are primary temporal evidence rather than independent support.
%
% These tests hold that seam open over the real shipped registry: every question
% the arbitrary-N agreement layer needs about potential support is answerable
% from exact relationship rows, and the answers stay distinguishable when two of
% them happen to share a count.
%
% Nothing here computes agreement. Potential support (what could be compared),
% realized availability (what this event carried), and observed outcome (what
% was within tolerance) are three separate dimensions; this suite covers only
% the first.
tests = functiontests(localfunctions);
end

% -------------------------------------------------------- the endpoint view ---

function testEndpointViewIsExactAndNonduplicative(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>
conn = fixture.conn;

% Exactly two rows per registered cross-extractor relationship, one per
% endpoint. A fan-out here would corrupt every counterpart count derived from it.
relationships = countOf(conn, "feature_relationships");
verifyEqual(testCase, relationships, 17);
verifyEqual(testCase, countOf(conn, "v_feature_relationship_endpoints"), ...
    2 * relationships);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(DISTINCT feature_relationship_id) " + ...
    "AS n FROM v_feature_relationship_endpoints"), relationships);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM (" + ...
    "SELECT feature_relationship_id, feature_id FROM v_feature_relationship_endpoints " + ...
    "GROUP BY feature_relationship_id, feature_id HAVING COUNT(*) > 1)"), 0);

% Each row orients one relationship from one side, and never points at itself
% or at its own extractor.
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM " + ...
    "v_feature_relationship_endpoints WHERE feature_id = counterpart_feature_id " + ...
    "OR extractor_id = counterpart_extractor_id"), 0);

% The view reports the registry verbatim: ineligible relationships are visible
% rather than filtered, because "no eligible counterpart" and "no counterpart at
% all" are different facts.
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM " + ...
    "v_feature_relationship_endpoints WHERE consilience_eligible = 0"), 4);
verifyEqual(testCase, scalar(conn, "SELECT COUNT(*) AS n FROM " + ...
    "v_feature_relationship_endpoints WHERE consilience_eligible = 0 " + ...
    "AND relationship_type <> 'related'"), 0);

clear cleanup
end

% ------------------------------------------- question 1: pair-level potential ---

function testEligibleNonTimingPotentialPerExtractorPairIsDerivable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% The policy decides which equivalence classes are reserved as primary temporal
% evidence; the database supplies the exact edges. Neither half is sufficient
% alone, which is why the classification is applied here at query time rather
% than stored on the feature.
rows = fetch(fixture.conn, ...
    "SELECT extractor_name, counterpart_extractor_name, COUNT(*) AS n " + ...
    "FROM v_feature_relationship_endpoints " + ...
    "WHERE consilience_eligible = 1 " + ...
    "AND feature_equivalence_class NOT IN " + timingClasses() + " " + ...
    "GROUP BY extractor_name, counterpart_extractor_name " + ...
    "ORDER BY extractor_name, counterpart_extractor_name");
verifyEqual(testCase, string(rows.extractor_name) + ">" + ...
    string(rows.counterpart_extractor_name), [ ...
    "DeepSqueak>MUPET"; "DeepSqueak>USVSEG"; "MUPET>DeepSqueak"; ...
    "MUPET>USVSEG"; "USVSEG>DeepSqueak"; "USVSEG>MUPET"]);
verifyEqual(testCase, double(rows.n), [4; 1; 4; 1; 1; 1]);

% This is the arithmetic that explains the Phase 1.5 observation: the
% specification requires two supporting comparisons within tolerance, and a
% USVSEG pairing has only one eligible non-timing relationship to offer. The
% explanation is derived from exact edges, so it stays true if a relationship is
% registered or withdrawn.
verifyEqual(testCase, fixture.minimum_supporting_comparisons, 2);
verifyEqual(testCase, nonTimingPotential(fixture, "DeepSqueak", "MUPET"), 4);
verifyEqual(testCase, nonTimingPotential(fixture, "DeepSqueak", "USVSEG"), 1);
verifyEqual(testCase, nonTimingPotential(fixture, "MUPET", "USVSEG"), 1);
verifyTrue(testCase, nonTimingPotential(fixture, "DeepSqueak", "USVSEG") < ...
    fixture.minimum_supporting_comparisons);

% Timing classes are present and eligible for every pair. A USVSEG pairing is
% not short of registered relationships; it is short of non-timing ones, and
% collapsing the two would misdescribe the extractor.
verifyEqual(testCase, allEligiblePotential(fixture, "DeepSqueak", "USVSEG"), 4);
verifyEqual(testCase, allEligiblePotential(fixture, "DeepSqueak", "MUPET"), 7);

clear cleanup
end

% ------------------------------------------ questions 2-4: counterpart sets ---

function testCounterpartIdentityCountAndAbsenceAreAllAnswerable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Which extractors hold an eligible counterpart for this feature, exactly.
verifyEqual(testCase, eligibleCounterparts(fixture, "DeepSqueak", ...
    "Principle Frequency (kHz)"), ["MUPET"; "USVSEG"]);
verifyEqual(testCase, eligibleCounterparts(fixture, "DeepSqueak", ...
    "Low Freq (kHz)"), "MUPET");
verifyEqual(testCase, eligibleCounterparts(fixture, "USVSEG", "meanfreq"), ...
    ["DeepSqueak"; "MUPET"]);
verifyEqual(testCase, eligibleCounterparts(fixture, "USVSEG", "maxfreq"), ...
    strings(0, 1));

% Distinct counterpart count against the possible N-1 for the selected set, and
% the exact identity of what is absent. Both come from the same rows.
selected = ["DeepSqueak", "MUPET", "USVSEG"];
verifyEqual(testCase, absentCounterparts(fixture, selected, "DeepSqueak", ...
    "Low Freq (kHz)"), "USVSEG");
verifyEqual(testCase, absentCounterparts(fixture, selected, "MUPET", ...
    "minimum frequency (kHz)"), "USVSEG");
verifyEqual(testCase, absentCounterparts(fixture, selected, "DeepSqueak", ...
    "Principle Frequency (kHz)"), strings(0, 1));
verifyEqual(testCase, absentCounterparts(fixture, selected, "USVSEG", ...
    "maxfreq"), ["DeepSqueak"; "MUPET"]);

% A shared equivalence class is not comparability. DeepSqueak's Peak Freq and
% USVSEG's maxfreq both sit in vocalization_peak_frequency and have no
% registered relationship at all, so neither reports the other as a counterpart.
verifyEqual(testCase, equivalenceClassOf(fixture, "DeepSqueak", "Peak Freq (kHz)"), ...
    "vocalization_peak_frequency");
verifyEqual(testCase, equivalenceClassOf(fixture, "USVSEG", "maxfreq"), ...
    "vocalization_peak_frequency");
verifyEqual(testCase, allCounterparts(fixture, "USVSEG", "maxfreq"), strings(0, 1));

clear cleanup
end

function testSameCountPatternsRemainDistinguishable(testCase)
[fixture, cleanup] = setUpFixture(); %#ok<ASGLU>

% Two DeepSqueak features whose distinct counterpart-extractor count is
% identical and whose evidence is not. Storing the count would make these two
% rows the same; the exact relationships keep them apart.
bandwidth = counterpartProfile(fixture, "DeepSqueak", "Delta Freq (kHz)");
power = counterpartProfile(fixture, "DeepSqueak", "Mean Power (dB/Hz)");
verifyEqual(testCase, bandwidth.counterpart_extractors, power.counterpart_extractors);
verifyEqual(testCase, bandwidth.counterpart_extractors, 1);

verifyEqual(testCase, bandwidth.counterpart_features, 1);
verifyEqual(testCase, power.counterpart_features, 2);
verifyEqual(testCase, bandwidth.eligible_counterparts, 1);
verifyEqual(testCase, power.eligible_counterparts, 0);
verifyEqual(testCase, bandwidth.counterparts, "MUPET:frequency bandwidth (kHz)");
verifyEqual(testCase, power.counterparts, ...
    "MUPET:total syllable energy (dB); MUPET:peak syllable amplitude (dB)");

% And two features whose counterpart count is zero for different reasons: one
% has an assessed counterpart that is registered as related but ineligible, the
% other has no registered counterpart at all.
verifyEqual(testCase, eligibleCounterparts(fixture, "MUPET", ...
    "peak syllable amplitude (dB)"), strings(0, 1));
verifyEqual(testCase, allCounterparts(fixture, "MUPET", ...
    "peak syllable amplitude (dB)"), "DeepSqueak");
verifyEqual(testCase, allCounterparts(fixture, "USVSEG", "maxamp"), strings(0, 1));

clear cleanup
end

% ------------------------------------------------------------------ helpers ---

function value = timingClasses()
%TIMINGCLASSES The specification's primary temporal evidence, as a SQL list.
%
% Read from the tracked specification rather than restated, so the test cannot
% silently disagree with the policy it is applying.
persistent cached
if isempty(cached)
    repoRoot = repoRootPath();
    document = jsondecode(fileread(fullfile(repoRoot, "config", ...
        "05_matching_profiles", "prototype_matching_consilience_spec.json")));
    classes = string(document.feature_support.timing_classes_reserved_as_primary_evidence);
    cached = "('" + strjoin(classes, "','") + "')";
end
value = cached;
end

function value = nonTimingPotential(fixture, extractorName, counterpartName)
value = scalar(fixture.conn, "SELECT COUNT(*) AS n FROM " + ...
    "v_feature_relationship_endpoints WHERE consilience_eligible = 1 " + ...
    "AND feature_equivalence_class NOT IN " + timingClasses() + " " + ...
    "AND extractor_name = " + sqlText(extractorName) + ...
    " AND counterpart_extractor_name = " + sqlText(counterpartName));
end

function value = allEligiblePotential(fixture, extractorName, counterpartName)
value = scalar(fixture.conn, "SELECT COUNT(*) AS n FROM " + ...
    "v_feature_relationship_endpoints WHERE consilience_eligible = 1 " + ...
    "AND extractor_name = " + sqlText(extractorName) + ...
    " AND counterpart_extractor_name = " + sqlText(counterpartName));
end

function value = eligibleCounterparts(fixture, extractorName, nativeName)
value = counterpartNames(fixture, extractorName, nativeName, ...
    " AND ep.consilience_eligible = 1");
end

function value = allCounterparts(fixture, extractorName, nativeName)
value = counterpartNames(fixture, extractorName, nativeName, "");
end

function value = counterpartNames(fixture, extractorName, nativeName, predicate)
rows = fetch(fixture.conn, "SELECT DISTINCT ep.counterpart_extractor_name AS name " + ...
    "FROM v_feature_relationship_endpoints ep " + ...
    "WHERE ep.extractor_name = " + sqlText(extractorName) + ...
    " AND ep.feature_native_name = " + sqlText(nativeName) + predicate + ...
    " ORDER BY name");
if height(rows) == 0
    value = strings(0, 1);
    return
end
value = string(rows.name);
value = value(:);
end

function value = absentCounterparts(fixture, selected, extractorName, nativeName)
%ABSENTCOUNTERPARTS Which of the selected extractors hold no eligible counterpart.
list = "('" + strjoin(selected, "','") + "')";
rows = fetch(fixture.conn, ...
    "WITH selected(extractor_name) AS (SELECT DISTINCT extractor_name " + ...
    "FROM v_feature_relationship_endpoints WHERE extractor_name IN " + list + ") " + ...
    "SELECT s.extractor_name AS name FROM selected s " + ...
    "WHERE s.extractor_name <> " + sqlText(extractorName) + ...
    " AND NOT EXISTS (SELECT 1 FROM v_feature_relationship_endpoints ep " + ...
    "WHERE ep.extractor_name = " + sqlText(extractorName) + ...
    " AND ep.feature_native_name = " + sqlText(nativeName) + ...
    " AND ep.consilience_eligible = 1 " + ...
    "AND ep.counterpart_extractor_name = s.extractor_name) ORDER BY name");
if height(rows) == 0
    value = strings(0, 1);
    return
end
value = string(rows.name);
value = value(:);
end

function value = counterpartProfile(fixture, extractorName, nativeName)
rows = fetch(fixture.conn, ...
    "SELECT COUNT(DISTINCT ep.counterpart_extractor_id) AS counterpart_extractors, " + ...
    "COUNT(*) AS counterpart_features, " + ...
    "SUM(ep.consilience_eligible) AS eligible_counterparts, " + ...
    "GROUP_CONCAT(ep.counterpart_extractor_name || ':' || " + ...
    "ep.counterpart_native_name, '; ') AS counterparts " + ...
    "FROM v_feature_relationship_endpoints ep " + ...
    "WHERE ep.extractor_name = " + sqlText(extractorName) + ...
    " AND ep.feature_native_name = " + sqlText(nativeName));
value = struct( ...
    counterpart_extractors=double(rows.counterpart_extractors(1)), ...
    counterpart_features=double(rows.counterpart_features(1)), ...
    eligible_counterparts=double(rows.eligible_counterparts(1)), ...
    counterparts=string(rows.counterparts(1)));
end

function value = equivalenceClassOf(fixture, extractorName, nativeName)
rows = fetch(fixture.conn, "SELECT IFNULL(xf.equivalence_class,'') AS value " + ...
    "FROM extractor_features xf " + ...
    "JOIN extractor_versions ev ON ev.extractor_version_id = xf.extractor_version_id " + ...
    "JOIN extractors e ON e.extractor_id = ev.extractor_id " + ...
    "WHERE e.extractor_name = " + sqlText(extractorName) + ...
    " AND xf.native_name = " + sqlText(nativeName));
value = string(rows.value(1));
end

function value = countOf(conn, tableName)
value = scalar(conn, "SELECT COUNT(*) AS n FROM " + tableName);
end

function value = scalar(conn, sql)
rows = fetch(conn, sql);
value = double(rows.(rows.Properties.VariableNames{1})(1));
end

function text = sqlText(value)
text = string(value);
text = "'" + replace(text, "'", "''") + "'";
end

function [fixture, cleanup] = setUpFixture()
repoRoot = repoRootPath();
addpath(fullfile(repoRoot, "src"));
scratch = string(tempname);
mkdir(scratch);
dbPath = fullfile(scratch, "registry.sqlite");
copyfile(registryTemplate(repoRoot), dbPath);
conn = sqlite(char(dbPath));
cleanup = onCleanup(@() tearDown(conn, scratch, repoRoot));
document = jsondecode(fileread(fullfile(repoRoot, "config", ...
    "05_matching_profiles", "prototype_matching_consilience_spec.json")));
fixture = struct(conn=conn, repo_root=repoRoot, scratch=scratch, ...
    minimum_supporting_comparisons=double( ...
        document.consilience.support_rule.minimum_supporting_comparisons));
end

function path = registryTemplate(repoRoot)
%REGISTRYTEMPLATE Schema plus the shipped semantic registry, built once.
persistent value
if isempty(value) || ~isfile(value)
    value = string(tempname) + ".sqlite";
    conn = sqlite(char(value), "create");
    closer = onCleanup(@() close(conn));
    vawlume.db.applySchema(conn, fullfile(repoRoot, "schema", "schema.sql"));
    vawlume.db.registerBuiltinSemantics(conn, repoRoot);
    delete(closer);
end
path = value;
end

function tearDown(conn, scratch, repoRoot)
try
    close(conn);
catch
end
if isfolder(scratch)
    rmdir(scratch, "s");
end
rmpath(fullfile(repoRoot, "src"));
end

function root = repoRootPath()
root = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
