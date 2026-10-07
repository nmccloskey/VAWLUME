function tests = test_combination_package_boundary
%TEST_COMBINATION_PACKAGE_BOUNDARY Revised invariant 5: combination has one home.
%
% Contract 06 D12, revised invariant 5, word for word:
%
%   Evidence dimensions are combined only inside src/+vawlume/+estimator/, by a
%   method whose settings profile states the five conditions. Nothing in
%   +attribution/, +acoustic/, +tracking/, +geometry/ or +alignment/ combines
%   them. +acoustic/'s level difference compares one dimension across two
%   channels and is not a combination.
%
% WHAT A COMBINATION LOOKS LIKE IN CODE. Contract 06 D7 combines by arithmetic on
% quantities from two evidence dimensions: a level difference (acoustic) minus a
% prediction from distances (pose/localization). Any real combination must, at
% some point, either put names from two dimensions into one arithmetic
% expression, or hand quantities from two dimensions to one function. So the
% guard reads every .m file under src/, strips string literals and comments, and
% lists:
%
%   1. every LINE that performs arithmetic (+ - * / ^, elementwise or not) and
%      names identifiers from two or more of the dimension vocabularies below;
%   2. every FUNCTION whose declared inputs (its signature) name identifiers from
%      two or more vocabularies -- this catches a combination whose arithmetic is
%      split across lines or hidden behind a helper.
%
% +estimator/ is permitted as a PACKAGE, because it is the one licensed home.
% Every other hit fails, unless it is a per-line exemption with a reason; there
% are none today. The vocabularies are matched as lower-case substrings of
% identifiers, so levelDifferenceDb, distance_a and pose_confidence all count.
%
% What it cannot see: a combination expressed through names that belong to no
% vocabulary (x = a - b where a and b were assigned elsewhere). The function
% check narrows that gap, and a reviewer reading +attribution/ closes the rest;
% the 6.12/6.13 sweeps read the estimator boundary.
%
% Phase 4's narrower guard on +attribution/
% (test_attribution_candidates_evidence/testNoAttributionFunctionCombinesEvidenceDimensions)
% is unchanged and still holds.
tests = functiontests(localfunctions);
end

function testCombinationArithmeticOccursOnlyInTheEstimatorPackage(testCase)
root = repositoryRoot();
[home, other] = combinationHits(root);
verifyEmpty(testCase, other, "Combination outside +estimator/:" + newline + ...
    strjoin(other, newline));
% The home is not vacuous: the method itself must be seen, or the scanner is
% blind to the very thing it guards.
verifyTrue(testCase, any(contains(home, "levelDifferenceConsistency.m")), ...
    "The scanner does not see the method's own combination.");
end

function testTheScannerFiresOnAnInjectedCombination(testCase)
% Negative controls, in memory: the shape the itinerary names (a function
% under +attribution/ that takes a distance and a level difference and returns
% a number), and each half of it on its own.
injected = [
    "function score = zzInject(distanceToMic, levelDifferenceDb)"
    "score = levelDifferenceDb - 20 * log10(distanceToMic);"
    "end"];
hits = violations("src/+vawlume/+attribution/zzInject.m", injected);
verifyEqual(testCase, numel(hits), 2, "Both the signature and the line fire.");
split = [
    "function y = zzSplit(poseDistance, acousticLevel)"
    "y = acousticLevel;"
    "end"];
verifyNotEmpty(testCase, violations("src/+vawlume/+tracking/zzSplit.m", split), ...
    "The signature check fires even with no arithmetic on any line.");
declared = [
    "function y = zzDeclared(a, b)"
    "arguments"
    "    a.distance_cm double"
    "    b.levelDifferenceDb double"
    "end"
    "y = 0;"
    "end"];
verifyNotEmpty(testCase, violations("src/+vawlume/+geometry/zzDeclared.m", declared), ...
    "An arguments block is a signature too.");
verifyNotEmpty(testCase, violations("src/+vawlume/+acoustic/zz.m", ...
    "x = identityValue * clockUncertaintyAlignment;"));
% And the things that are not combinations stay silent.
verifyEmpty(testCase, violations("src/+vawlume/+acoustic/zz.m", ...
    "value = 10 * log10(a.value / b.value); % acoustic level vs distance"));
verifyEmpty(testCase, violations("src/+vawlume/+acoustic/zz.m", ...
    "label = ""distance"" + acousticKey;"));
verifyEmpty(testCase, violations("src/+vawlume/+estimator/zz.m", injected), ...
    "+estimator/ is the licensed home.");
end

% --------------------------------------------------------------- scanner ---

function [home, other] = combinationHits(root)
files = dir(fullfile(root, "src", "**", "*.m"));
home = strings(0, 1);
other = strings(0, 1);
for index = 1:numel(files)
    path = fullfile(files(index).folder, files(index).name);
    relative = replace(extractAfter(string(path), strlength(string(root)) + 1), "\", "/");
    lines = splitlines(string(fileread(path)));
    if isHome(relative)
        home = [home; scanLines(relative, lines)]; %#ok<AGROW>
    else
        other = [other; violations(relative, lines)]; %#ok<AGROW>
    end
end
end

function hits = violations(relative, lines)
% Combination hits that the boundary forbids: anywhere but the licensed home,
% minus the per-line exemptions.
hits = strings(0, 1);
if isHome(relative)
    return
end
hits = setdiff(scanLines(relative, lines), permittedCombination());
end

function value = isHome(relative)
value = startsWith(relative, "src/+vawlume/+estimator/");
end

function hits = scanLines(relative, lines)
hits = strings(0, 1);
inBlockComment = false;
inArguments = false;
signature = "";
for lineNumber = 1:numel(lines)
    trimmed = strtrim(lines(lineNumber));
    if trimmed == "%{"
        inBlockComment = true;
        continue
    elseif trimmed == "%}"
        inBlockComment = false;
        continue
    elseif inBlockComment
        continue
    end
    code = stripCode(lines(lineNumber));
    if strlength(code) == 0
        continue
    end
    if startsWith(code, "function ")
        signature = code;
        inputs = "";
        if contains(code, "(")
            inputs = extractAfter(code, "(");
        end
        if numel(families(inputs)) >= 2
            hits(end + 1, 1) = relative + " | signature | " + code; %#ok<AGROW>
        end
        continue
    end
    % Arguments-block lines are declared inputs too.
    if code == "arguments"
        inArguments = true;
        argumentLines = strings(0, 1);
        continue
    elseif inArguments && code == "end"
        inArguments = false;
        if numel(families(strjoin(argumentLines, " "))) >= 2
            hits(end + 1, 1) = relative + " | arguments | " + signature; %#ok<AGROW>
        end
        continue
    elseif inArguments
        argumentLines(end + 1, 1) = code; %#ok<AGROW>
        continue
    end
    if ~isempty(regexp(code, arithmeticPattern(), "once")) && numel(families(code)) >= 2
        hits(end + 1, 1) = relative + " | " + code; %#ok<AGROW>
    end
end
end

function found = families(code)
% The four upstream evidence dimensions' vocabularies (contract 06 D10). A
% bare "pose" is not a term, because it is inside "compose" and "purpose".
vocabulary = struct( ...
    acoustic=["acoustic", "leveldifference", "level_difference", "band_power", ...
        "bandpower", "rms_amplitude", "delta_l", "deltal", "observed_db"], ...
    pose_localization=["distance", "position", "bodypoint", "pose_", "poseconf", ...
        "posedistance"], ...
    visual_identity=["identity", "association"], ...
    temporal_alignment=["alignment", "uncertainty_s", "clockuncertainty", ...
        "clock_uncertainty"]);
identifiers = lower(string(regexp(char(code), "[A-Za-z_]\w*", "match")));
found = strings(0, 1);
for name = string(fieldnames(vocabulary))'
    if any(contains(identifiers, vocabulary.(name)))
        found(end + 1, 1) = name; %#ok<AGROW>
    end
end
end

function pattern = arithmeticPattern()
% A binary arithmetic operator between two operands: identifier, number, or a
% closing/opening bracket. Elementwise forms included.
pattern = "[\w)\]]\s*\.?[-+*/\\^]\s*[\w(\[]";
end

function value = permittedCombination()
% Per-line exemptions outside +estimator/, each with its reason. Never a package.
value = strings(0, 1);
end

function code = stripCode(line)
% Remove string literals, then everything from a comment or continuation on.
% A single quote opens a char array only where a transpose is impossible.
chars = char(line);
out = blanks(0);
index = 1;
count = numel(chars);
while index <= count
    c = chars(index);
    if c == '"'
        index = skipQuoted(chars, index, '"');
        continue
    elseif c == '''' && ~isTranspose(out)
        index = skipQuoted(chars, index, '''');
        continue
    elseif c == '%'
        break
    elseif c == '.' && index + 2 <= count && all(chars(index:index+2) == '...')
        break
    end
    out(end+1) = c; %#ok<AGROW>
    index = index + 1;
end
code = strtrim(string(out));
end

function index = skipQuoted(chars, index, quote)
index = index + 1;
while index <= numel(chars)
    if chars(index) == quote
        if index < numel(chars) && chars(index + 1) == quote
            index = index + 2;
            continue
        end
        index = index + 1;
        return
    end
    index = index + 1;
end
end

function value = isTranspose(previous)
value = false;
if isempty(previous)
    return
end
last = previous(end);
value = isletter(last) || (last >= '0' && last <= '9') || ...
    any(last == ['_', ')', ']', '}', '.', '''']);
end

function root = repositoryRoot()
root = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
end
