function tests = test_agreement_components
%TEST_AGREEMENT_COMPONENTS The arbitrary-N graph contract, without a database.
%
% vawlume.agreement.internal.connectedComponents takes node identifiers and
% undirected edges. It knows nothing about detections, extractors, or how many
% participants there are, which is the property this suite exists to hold: the
% composition path has no place to acquire a hard-coded number of extractors.
%
% Node identifiers here are written as EXX where E is an extractor ordinal, so
% the shapes are readable as extractor participation. That encoding is the
% test's convention only; the function never decodes it.
%
% Two distinctions the suite protects. Connectivity is not completeness: a
% component says its nodes are connected, never that every pair among them is
% linked. And an isolated node is a component, because an extractor-unique
% detection has to survive composition.
tests = functiontests(localfunctions);
end

% -------------------------------------------------------------- three nodes ---

function testCompleteTriangleAndOpenChainAreTheSameComponentButNotTheSameGraph(testCase)
triangleNodes = [101; 201; 301];
triangle = components(triangleNodes, [101 201; 201 301; 101 301]);
chain = components(triangleNodes, [101 201; 201 301]);

% Both are one component over the same three nodes. The component alone cannot
% tell them apart, which is exactly why the composition layer stores the exact
% edges and never infers completeness from membership.
verifyEqual(testCase, triangle, chain);
verifyEqual(testCase, numel(unique(triangle.component_ordinal)), 1);
verifyEqual(testCase, triangle.node_id, triangleNodes);

% The distinction lives in the edge count the caller keeps beside them: three
% edges for the triangle, two for the chain. Nothing here invents the third.
verifyEqual(testCase, 3, height(edgeTable([101 201; 201 301; 101 301])));
verifyEqual(testCase, 2, height(edgeTable([101 201; 201 301])));
end

function testPairOnlyAndIsolatedNodesAreSeparateComponents(testCase)
assignment = components([101; 201; 301], [101 201]);
verifyEqual(testCase, assignment.node_id, [101; 201; 301]);
verifyEqual(testCase, assignment.component_ordinal, [1; 1; 2]);

% Every node is placed. An extractor-unique detection is a single-member
% component rather than a dropped row.
isolated = components([101; 201; 301], zeros(0, 2));
verifyEqual(testCase, isolated.component_ordinal, [1; 2; 3]);
verifyEqual(testCase, height(isolated), 3);
end

% --------------------------------------------------------- arbitrary N > 3 ---

function testFourExtractorShapesAreDistinguishable(testCase)
nodes = [101; 201; 301; 401];

% A complete K4 over four extractors.
complete = components(nodes, [101 201; 101 301; 101 401; 201 301; 201 401; 301 401]);
verifyEqual(testCase, numel(unique(complete.component_ordinal)), 1);
verifyEqual(testCase, complete.node_id, nodes);

% A four-node open chain: one component, three edges, three unsupported pairs.
chain = components(nodes, [101 201; 201 301; 301 401]);
verifyEqual(testCase, chain, complete);

% K4 with one edge removed is still one component. Membership is unchanged and
% only the stored edge list records the missing 1-4 pair.
missingOne = components(nodes, [101 201; 101 301; 201 301; 201 401; 301 401]);
verifyEqual(testCase, missingOne, complete);

% Two disjoint pairs across four extractors are two components.
split = components(nodes, [101 201; 301 401]);
verifyEqual(testCase, split.component_ordinal, [1; 1; 2; 2]);
end

function testFiveExtractorsWithMultipleDetectionsPerExtractor(testCase)
% Five extractors, and extractor 2 contributes two detections to one component.
% Coarse support is summarized at the extractor-pair level by the caller; this
% function just keeps all the nodes and all the edges.
nodes = [101; 201; 202; 301; 401; 402; 501];
assignment = components(nodes, [ ...
    101 201; 101 202; 201 301; ...   % extractor 1-2 twice, then 2-3
    401 402; ...                     % extractor 4's two detections are unlinked here
    401 501]);
verifyEqual(testCase, assignment.node_id, nodes);
verifyEqual(testCase, assignment.component_ordinal, [1; 1; 1; 1; 2; 2; 2]);
verifyEqual(testCase, numel(unique(assignment.component_ordinal)), 2);

% Nothing about the result depends on there being three, four, or five
% extractors: the same call handles a twelve-participant graph.
wide = (1:12)' * 100 + 1;
star = [repmat(wide(1), 11, 1), wide(2:end)];
verifyEqual(testCase, numel(unique(components(wide, star).component_ordinal)), 1);
end

% ------------------------------------------------------------- determinism ---

function testResultIsIndependentOfNodeAndEdgeOrder(testCase)
nodes = [101; 201; 202; 301; 401];
edges = [201 301; 101 201; 401 202];
expected = components(nodes, edges);

verifyEqual(testCase, components(flip(nodes), edges), expected);
verifyEqual(testCase, components(nodes, flip(edges, 1)), expected);
verifyEqual(testCase, components(nodes([3 1 5 2 4]), edges([3 1 2], :)), expected);

% Reversing an edge's endpoints cannot matter: support is undirected.
reversed = edges(:, [2 1]);
verifyEqual(testCase, components(nodes, reversed), expected);

% Components are ordered by their smallest node, and members ascend within a
% component. Stored component identity depends on that being fixed.
verifyEqual(testCase, expected.node_id, [101; 201; 301; 202; 401]);
verifyEqual(testCase, expected.component_ordinal, [1; 1; 1; 2; 2]);
end

function testEmptyGraphIsEmptyRatherThanAnError(testCase)
assignment = components(zeros(0, 1), zeros(0, 2));
verifyEqual(testCase, height(assignment), 0);
verifyEqual(testCase, string(assignment.Properties.VariableNames), ...
    ["node_id", "component_ordinal"]);

% Edges are optional, because a run where no pair corresponded is a legal
% result made entirely of singletons.
verifyEqual(testCase, height(components([101; 201])), 2);
end

% ----------------------------------------------------------- invalid inputs ---

function testMalformedGraphsAreRefusedNotRepaired(testCase)
verifyError(testCase, @() components([101; 101], zeros(0, 2)), ...
    "vawlume:agreement:GraphNodeInvalid");
verifyError(testCase, @() components([101; 0], zeros(0, 2)), ...
    "vawlume:agreement:GraphNodeInvalid");
verifyError(testCase, @() components([101; 1.5], zeros(0, 2)), ...
    "vawlume:agreement:GraphNodeInvalid");

% An edge to a node outside the participating set would silently widen the
% population, so it is refused.
verifyError(testCase, @() components([101; 201], [101 999]), ...
    "vawlume:agreement:GraphNodeUnknown");

% A self-edge carries no correspondence evidence: a detection cannot corroborate
% itself, and accepting one would let a singleton claim support.
verifyError(testCase, @() components([101; 201], [101 101]), ...
    "vawlume:agreement:GraphEdgeInvalid");
verifyError(testCase, @() components([101; 201], [101 NaN]), ...
    "vawlume:agreement:GraphEdgeInvalid");
end

% ------------------------------------------------------------------ helpers ---

function assignment = components(nodeIds, edges)
if nargin < 2
    assignment = vawlume.agreement.internal.connectedComponents(nodeIds);
    return
end
assignment = vawlume.agreement.internal.connectedComponents(nodeIds, edges);
end

function value = edgeTable(edges)
%EDGETABLE The caller's exact edge list, which the component never replaces.
value = table(edges(:, 1), edges(:, 2), VariableNames=["node_a", "node_b"]);
end

function setupOnce(testCase) %#ok<*DEFNU>
repoRoot = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repo_root = repoRoot;
end

function teardownOnce(testCase)
rmpath(fullfile(testCase.TestData.repo_root, "src"));
end
