function assignment = connectedComponents(nodeIds, edges)
%CONNECTEDCOMPONENTS Deterministic connected components over an arbitrary graph.
%
% ASSIGNMENT = vawlume.agreement.internal.connectedComponents(NODEIDS, EDGES)
% returns a table of node_id and component_ordinal. NODEIDS is a vector of
% distinct positive integer node identifiers; EDGES is an N-by-2 matrix of node
% identifier pairs, both of which must appear in NODEIDS.
%
% This function knows nothing about detections, extractors, recordings, or
% extractor counts. It takes node identifiers and undirected edges, which is why
% the arbitrary-N composition path has no place to acquire a hard-coded number
% of extractors: three, four, or twelve participants are the same problem here.
%
% Isolated nodes are components. An extractor-unique detection has to survive
% composition as a single-member group, so a node with no edges is not dropped.
%
% No edge is invented. The component containing several nodes says only that
% they are connected, never that every pair among them is supported; that
% distinction is the caller's to report from the exact edge list.
%
% Determinism is part of the contract, because stored component identity depends
% on it: components are ordered by their smallest node identifier ascending, and
% the result is ordered by component ordinal then node identifier. Permuting
% NODEIDS or the rows of EDGES cannot change the output.
%
% It lives in +internal rather than the package's private folder so that the
% graph contract can be unit tested on synthetic inputs without a database.

arguments
    nodeIds (:,1) double
    edges (:,2) double = zeros(0, 2)
end

validateNodes(nodeIds);
validateEdges(edges, nodeIds);

nodes = sort(nodeIds);
parent = (1:numel(nodes))';
for index = 1:size(edges, 1)
    left = find(nodes == edges(index, 1), 1);
    right = find(nodes == edges(index, 2), 1);
    parent = unite(parent, left, right);
end
for index = 1:numel(parent)
    [parent, parent(index)] = rootOf(parent, index);
end

roots = unique(parent);
minimumNode = zeros(numel(roots), 1);
for index = 1:numel(roots)
    minimumNode(index) = min(nodes(parent == roots(index)));
end
[~, order] = sort(minimumNode);
roots = roots(order);

nodeId = zeros(numel(nodes), 1);
componentOrdinal = zeros(numel(nodes), 1);
filled = 0;
for ordinal = 1:numel(roots)
    selected = sort(nodes(parent == roots(ordinal)));
    span = filled + (1:numel(selected));
    nodeId(span) = selected;
    componentOrdinal(span) = ordinal;
    filled = filled + numel(selected);
end
assignment = table(nodeId, componentOrdinal, ...
    VariableNames=["node_id", "component_ordinal"]);
end

function validateNodes(nodeIds)
if isempty(nodeIds)
    return
end
if any(~isfinite(nodeIds)) || any(nodeIds <= 0) || ...
        any(nodeIds ~= floor(nodeIds))
    error("vawlume:agreement:GraphNodeInvalid", ...
        "Node identifiers must be finite positive integers.");
end
if numel(unique(nodeIds)) ~= numel(nodeIds)
    error("vawlume:agreement:GraphNodeInvalid", ...
        "Node identifiers must be distinct.");
end
end

function validateEdges(edges, nodeIds)
if isempty(edges)
    return
end
if any(~isfinite(edges(:)))
    error("vawlume:agreement:GraphEdgeInvalid", ...
        "Edge endpoints must be finite.");
end
if any(edges(:, 1) == edges(:, 2))
    error("vawlume:agreement:GraphEdgeInvalid", ...
        "A self-edge carries no correspondence evidence.");
end
unknown = edges(~ismember(edges, nodeIds));
if ~isempty(unknown)
    error("vawlume:agreement:GraphNodeUnknown", ...
        "Edge endpoint(s) %s are not in the node set.", ...
        strjoin(string(unique(unknown(:))'), ", "));
end
end

function parent = unite(parent, left, right)
[parent, leftRoot] = rootOf(parent, left);
[parent, rightRoot] = rootOf(parent, right);
if leftRoot ~= rightRoot
    if leftRoot < rightRoot
        parent(rightRoot) = leftRoot;
    else
        parent(leftRoot) = rightRoot;
    end
end
end

function [parent, root] = rootOf(parent, node)
root = node;
while parent(root) ~= root
    root = parent(root);
end
while parent(node) ~= node
    next = parent(node);
    parent(node) = root;
    node = next;
end
end
