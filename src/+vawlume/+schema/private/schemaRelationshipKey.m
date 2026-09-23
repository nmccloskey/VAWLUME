function keys = schemaRelationshipKey(sourceTable, sourceColumns, targetTable, targetColumns)
%SCHEMARELATIONSHIPKEY The identity of a relationship, as one comparable string.
%
% The key is the 4-tuple (source_table, source_columns, target_table,
% target_columns). Measured during Part 1: this tuple is unique across all 245
% structural relations, with zero exact duplicates.
%
% A (child, parent) key alone would NOT have sufficed. Nine object pairs carry
% two distinct relations each -- `candidate_pairs` to `detections`,
% `time_alignment_runs` to `timebases`, and seven others -- and only the columns
% separate them.
%
% `source` is always the child, the table holding the foreign key. Direction is
% part of the identity, which is what makes a reversed authored entry
% detectable rather than merely wrong.

arguments
    sourceTable (:,1) string
    sourceColumns (:,1) string
    targetTable (:,1) string
    targetColumns (:,1) string
end

keys = sourceTable + "(" + sourceColumns + ")->" + ...
    targetTable + "(" + targetColumns + ")";
end
