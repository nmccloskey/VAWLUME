function tests = test_policy_rule_declarations
%TEST_POLICY_RULE_DECLARATIONS Every decision rule states what it can produce (7.17 F2).
%
% attributionLoadPolicy declares each implemented decision rule once, with the
% statuses it can produce; compare reads that set to tell a structural empty
% from a disagreement (contract 07 D4). Before 7.17a an unlisted rule silently
% received a four-status default, so a new rule able to say "simultaneous" would
% have been misread. These guards read the source: every rule key the decision
% planner dispatches on is declared with a producible set, every declared rule
% is dispatched, and no default set remains.
tests = functiontests(localfunctions);
end

function testEveryDispatchedRuleDeclaresItsProducibleStatuses(testCase)
[declared, dispatched] = ruleKeys();
verifyNotEmpty(testCase, dispatched, "No rule key found in the decision planner.");
verifyEqual(testCase, sort(declared), sort(dispatched), ...
    "Declared rules (attributionLoadPolicy) and dispatched rules " + ...
    "(attributionBuildDecisionPlan) differ.");
end

function testOnlyTheCoOccurrenceRuleCanSaySimultaneous(testCase)
text = policySource();
block = extractBetween(text, "function value = implementedRuleStatuses()", ...
    newline + "end");
verifyNotEmpty(testCase, block);
entries = regexp(block{1}, "(\w+)=\[([^\]]*)\]", "tokens");
for k = 1:numel(entries)
    rule = string(entries{k}{1});
    canSay = contains(entries{k}{2}, """simultaneous""");
    verifyEqual(testCase, canSay, contains(rule, "co_occurrence"), rule);
end
end

function testNoDefaultProducibleSetRemains(testCase)
code = codeLines(policyFile());
hits = code(contains(code, "otherwise") | contains(code, "producible_statuses = ["));
verifyEmpty(testCase, hits, "A default producible set: " + strjoin(hits, " | "));
end

% ------------------------------------------------------------- helpers ---

function [declared, dispatched] = ruleKeys()
text = policySource();
block = extractBetween(text, "function value = implementedRuleStatuses()", ...
    newline + "end");
declared = string(regexp(block{1}, "(\w+)=\[", "tokens"));
declared = unique(declared(:))';
planner = string(fileread(fullfile(privateFolder(), "attributionBuildDecisionPlan.m")));
dispatched = string(regexp(planner, "rule_key\s*==\s*""(\w+)""", "tokens"));
dispatched = unique(dispatched(:))';
end

function text = policySource()
text = replace(string(fileread(policyFile())), string([char(13) char(10)]), newline);
end

function path = policyFile()
path = fullfile(privateFolder(), "attributionLoadPolicy.m");
end

function folder = privateFolder()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
folder = fullfile(root, "src", "+vawlume", "+attribution", "private");
end

function code = codeLines(file)
lines = splitlines(string(fileread(file)));
lines = lines(~startsWith(strtrim(lines), "%"));
code = regexprep(lines, "%.*$", "");
code = code(strlength(strtrim(code)) > 0)';
end
