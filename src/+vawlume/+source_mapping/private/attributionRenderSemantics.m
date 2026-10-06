function value = attributionRenderSemantics(declared, producer)
%ATTRIBUTIONRENDERSEMANTICS Render a declared semantics string so it names its producer.
%
% Shared by every attribution mapper: a stored semantics string must NAME the
% system that produced the number, not point at a file the reader may not have.
% F4-1.
%
% Two mechanisms, because a profile VAWLUME did not ship cannot be relied on to
% cooperate:
%
%   1. {producer} is substituted wherever the profile declares it, so an author
%      controls where the name appears in their own sentence.
%   2. If the rendered string still does not contain the producer's name,
%      "; producer=<name>" is appended.
%
% The append looks like VAWLUME editing somebody's declaration and is not. This
% string is PROSE VAWLUME COMPOSES from facts the profile declared -- the
% producer's name is declared in the same file. Composing two declarations is
% not inventing one. The rule that forbids recomputation governs the NUMBER, and
% no number is touched here.
value = strtrim(declared);
if strlength(value) == 0 || strlength(producer) == 0
    return
end
value = replace(value, "{producer}", producer);
if ~contains(value, producer)
    value = value + "; producer=" + producer;
end
end
