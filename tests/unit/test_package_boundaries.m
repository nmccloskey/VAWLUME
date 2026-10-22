function tests = test_package_boundaries
%TEST_PACKAGE_BOUNDARIES Static guards over src/: dependency direction and path resolution.
%
% Plan §12 integration check 6 (shared correspondence utilities create no
% semantic coupling) and contract 07 closure invariants 53 and 54. Both read
% CODE: string literals and comments are stripped first, so help text and error
% prose that name another package are never a dependency.
tests = functiontests(localfunctions);
end

% ------------------------------------------------- dependency direction (E11) ---

function testSharedPrimitivesAndAttributionDependOnlyWhereAllowed(testCase)
% Invariant 53, word for word: +attribution/ depends only on +alignment's
% transform appliers, +geometry.assertCompatible, +interval, +db and +schema.
% +interval depends on no VAWLUME package, and +matching only on +interval.
% Check 6 adds: +agreement's composition calls no domain package.
%
% vawlume.internal.resolvePath is permitted everywhere: it is the one home for
% path resolution (D14, invariant 54), which 7.11 placed in these packages by
% design, and it carries no domain semantics.
violations = strings(0, 1);
for rule = dependencyRules()
    used = packageReferences(repositoryRoot(), rule.package);
    for k = 1:height(used)
        if ~allowedReference(rule, used.package(k), used.name(k))
            violations(end + 1, 1) = rule.package + " -> vawlume." + ...
                used.package(k) + "." + used.name(k) + "  (" + used.where(k) + ")"; %#ok<AGROW>
        end
    end
end
verifyEmpty(testCase, violations, ...
    "Package dependencies outside the allowed direction:" + newline + ...
    strjoin(violations, newline));
end

function testTheDependencyScannerSeesCodeAndNotProse(testCase)
% A guard that finds nothing proves nothing until it has been seen to find
% something: each scanned package does reference at least one package, and
% prose naming a package is not a reference.
for package = ["matching", "attribution", "agreement"]
    verifyNotEmpty(testCase, packageReferences(repositoryRoot(), package), ...
        "No vawlume.* reference was found in +" + package + ".");
end
verifyEqual(testCase, referencesIn("x = vawlume.estimator.loadSettings(p);"), ...
    "estimator.loadSettings");
verifyEmpty(testCase, referencesIn("% see vawlume.estimator.loadSettings"));
verifyEmpty(testCase, referencesIn("error(""id"", ""use vawlume.estimator.x"");"));
verifyEmpty(testCase, referencesIn("s = 'vawlume.tracking.readWindow';"));
end

% -------------------------------------------------- path resolution (7.11) ---

function testTheJavaFileIdiomAppearsOnlyInItsHome(testCase)
% Invariant 54 / 7.11: caller-supplied paths resolve through
% vawlume.internal.resolvePath. java.io.File(...) resolves a relative path
% against the JVM's user.dir, so no other file may construct one. Its documented
% wrappers (doc 49) call the home and contain no Java.
home = "src/+vawlume/+internal/resolvePath.m";
hits = strings(0, 1);
homeHits = 0;
for file = sourceFiles(repositoryRoot(), "src")
    for code = codeLines(file.path)'
        if ~isempty(regexp(code, "java\.io\.File\(", "once"))
            if file.relative == home
                homeHits = homeHits + 1;
            else
                hits(end + 1, 1) = file.relative + " | " + code; %#ok<AGROW>
            end
        end
    end
end
verifyGreaterThan(testCase, homeHits, 0, ...
    "The home itself no longer constructs a java.io.File; the pattern is stale.");
verifyEmpty(testCase, hits, ...
    "java.io.File outside vawlume.internal.resolvePath:" + newline + ...
    strjoin(hits, newline));
end

% ---------------------------------------------------------------- helpers ---

function rules = dependencyRules()
appliers = ["applyTransform", "applyTransformInterval", "applyInverseTransform"];
domain = ["attribution", "estimator", "acoustic", "tracking", "eda"];
rules = [ ...
    struct(package="interval", allowed=strings(1, 0), functions=struct(), forbidden=strings(1, 0)), ...
    struct(package="matching", allowed="interval", functions=struct(), forbidden=strings(1, 0)), ...
    struct(package="attribution", allowed=["interval", "db", "schema"], ...
        functions=struct(alignment=appliers, geometry="assertCompatible"), ...
        forbidden=strings(1, 0)), ...
    struct(package="agreement", allowed=strings(1, 0), functions=struct(), ...
        forbidden=domain)];
end

function ok = allowedReference(rule, package, name)
if package == rule.package || (package == "internal" && name == "resolvePath")
    ok = true;
elseif ~isempty(rule.forbidden)
    % A deny rule: anything but the named domain packages.
    ok = ~ismember(package, rule.forbidden);
elseif ismember(package, rule.allowed)
    ok = true;
elseif isfield(rule.functions, package)
    ok = ismember(name, rule.functions.(package));
else
    ok = false;
end
end

function used = packageReferences(root, package)
used = table(strings(0, 1), strings(0, 1), strings(0, 1), ...
    VariableNames=["package", "name", "where"]);
for file = sourceFiles(root, fullfile("src", "+vawlume", "+" + package))
    for code = codeLines(file.path)'
        for reference = referencesIn(code)
            parts = split(reference, ".");
            used(end + 1, :) = {parts(1), parts(2), file.relative}; %#ok<AGROW>
        end
    end
end
end

function references = referencesIn(line)
tokens = regexp(stripCode(line), "\<vawlume\.(\w+)\.(\w+)", "tokens");
references = strings(1, 0);
for k = 1:numel(tokens)
    references(end + 1) = string(tokens{k}{1}) + "." + string(tokens{k}{2}); %#ok<AGROW>
end
end

function files = sourceFiles(root, folder)
listing = dir(fullfile(root, folder, "**", "*.m"));
files = struct("path", {}, "relative", {});
for k = 1:numel(listing)
    path = string(fullfile(listing(k).folder, listing(k).name));
    files(end + 1) = struct(path=path, relative=replace(extractAfter(path, ...
        strlength(string(root)) + 1), "\", "/")); %#ok<AGROW>
end
end

function lines = codeLines(path)
raw = splitlines(string(fileread(path)));
lines = strings(0, 1);
inBlockComment = false;
for k = 1:numel(raw)
    trimmed = strtrim(raw(k));
    if trimmed == "%{"
        inBlockComment = true;
        continue
    elseif trimmed == "%}"
        inBlockComment = false;
        continue
    elseif inBlockComment
        continue
    end
    code = stripCode(raw(k));
    if strlength(code) > 0
        lines(end + 1, 1) = code; %#ok<AGROW>
    end
end
end

function code = stripCode(line)
% Remove string literals, then everything from a comment or a continuation on;
% the machinery of test_localization_evidence's arithmetic scanners.
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
