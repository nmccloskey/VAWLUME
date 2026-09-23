function issue = schemaDescriptionIssue(description, identifier)
%SCHEMADESCRIPTIONISSUE Why a description is unacceptable, or "" if it is fine.
%
% Machine-checkable half of the completeness rule. It cannot detect prose that
% is thoughtful-looking and wrong -- that is what Part 3's manual cross-domain
% sample is for -- but it does catch the cheap ways of appearing to have
% described 1,155 columns.
%
% The de-underscored-name test is the one that matters. "Detection score" as
% the description of `detection_score` conveys nothing a reader did not already
% have, and at this scale it is the filler that would otherwise accumulate.

arguments
    description string
    identifier (1,1) string = ""
end

issue = "";

if ~isscalar(description) || ismissing(description)
    issue = "must be a single string";
    return
end

trimmed = strtrim(description);

if strlength(trimmed) == 0
    issue = "must not be empty";
    return
end

if strlength(trimmed) < 15
    issue = sprintf("is %d characters; a description must be at least 15", ...
        strlength(trimmed));
    return
end

placeholders = ["TODO", "TBD", "FIXME", "???", "XXX"];
upperText = upper(trimmed);
found = placeholders(contains(upperText, placeholders));
if ~isempty(found)
    issue = "contains the placeholder " + found(1);
    return
end

if identifier ~= "" && schemaNormalizeForFillerTest(trimmed) == ...
        schemaNormalizeForFillerTest(replace(identifier, "_", " "))
    issue = "only restates the name """ + identifier + """";
    return
end
end
