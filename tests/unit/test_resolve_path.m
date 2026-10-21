function tests = test_resolve_path
%TEST_RESOLVE_PATH The one home for path resolution, vawlume.internal.resolvePath.
%
% Every test that resolves a relative path runs with MATLAB's current folder
% deliberately different from the JVM's user.dir. Java resolves a relative path
% against user.dir, which MATLAB's cd never moves; the helper must not.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = string(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repoRoot, "src"));
testCase.addTeardown(@() rmpath(fullfile(repoRoot, "src")));
end

function setup(testCase)
% A disposable area whose names hold a space and a non-ASCII character, with a
% caller folder made current and a separate base folder.
area = fullfile(tempdir, "vawlume resolve " + string(java.util.UUID.randomUUID));
caller = fullfile(area, "cal ler " + char(233));
base = fullfile(area, "ba se " + char(252));
mkdir(fullfile(caller, "c d"));
mkdir(fullfile(base, "a b"));
testCase.TestData.area = canonical(area);
testCase.TestData.caller = canonical(caller);
testCase.TestData.base = canonical(base);
testCase.addTeardown(@() rmdir(area, "s"));
userDir = string(java.lang.System.getProperty("user.dir"));
previous = cd(caller);
testCase.addTeardown(@() cd(previous));
assumeNotEqual(testCase, lower(canonical(pwd)), lower(canonical(userDir)), ...
    "The current folder must differ from the JVM's user.dir.");
end

function testAnAbsolutePathIsReturnedCanonical(testCase)
base = testCase.TestData.base;
value = vawlume.internal.resolvePath(fullfile(base, "a b", "..", "a b", "f.json"));
verifyEqual(testCase, value, string(fullfile(base, "a b", "f.json")));
end

function testACallerRelativePathResolvesAgainstTheCurrentFolderNotUserDir(testCase)
value = vawlume.internal.resolvePath("c d/../c d/f.json");
verifyEqual(testCase, value, string(fullfile(testCase.TestData.caller, "c d", "f.json")));
verifyEqual(testCase, vawlume.internal.resolvePath(""), testCase.TestData.caller);
end

function testABaseRelativePathResolvesAgainstItsBaseNotTheCurrentFolder(testCase)
base = testCase.TestData.base;
verifyEqual(testCase, vawlume.internal.resolvePath("a b/f.json", Base=base), ...
    string(fullfile(base, "a b", "f.json")));
% A relative base is itself resolved against the current folder.
verifyEqual(testCase, vawlume.internal.resolvePath("a b/f.json", ...
    Base="../ba se " + char(252)), string(fullfile(base, "a b", "f.json")));
% An absolute path ignores the base.
absolute = fullfile(testCase.TestData.caller, "c d", "f.json");
verifyEqual(testCase, vawlume.internal.resolvePath(absolute, Base=base), string(absolute));
end

function testAnEmptyBaseIsRefused(testCase)
verifyError(testCase, @() vawlume.internal.resolvePath("f.json", Base=""), ...
    "vawlume:internal:InvalidBase");
end

function testAbsoluteModeKeepsDotSegmentsAndCanonicalModeRemovesThem(testCase)
caller = testCase.TestData.caller;
verifyEqual(testCase, vawlume.internal.resolvePath("c d/../f.json", Mode="absolute"), ...
    string(fullfile(caller, "c d", "..", "f.json")));
verifyEqual(testCase, vawlume.internal.resolvePath("c d/../f.json"), ...
    string(fullfile(caller, "f.json")));
end

function testThePredicateResolvesNothingAndRefusesNothing(testCase)
verifyTrue(testCase, vawlume.internal.resolvePath(testCase.TestData.base, Mode="isAbsolute"));
verifyFalse(testCase, vawlume.internal.resolvePath("a b/f.json", Mode="isAbsolute"));
verifyFalse(testCase, vawlume.internal.resolvePath("", Mode="isAbsolute"));
if ispc
    verifyFalse(testCase, vawlume.internal.resolvePath("C:x\f.json", Mode="isAbsolute"));
    verifyFalse(testCase, vawlume.internal.resolvePath("\x\f.json", Mode="isAbsolute"));
end
end

function testNoCaseIsFolded(testCase)
value = vawlume.internal.resolvePath("Mixed Case/NoSuch.JSON");
verifyEqual(testCase, value, string(fullfile(testCase.TestData.caller, ...
    "Mixed Case", "NoSuch.JSON")));
end

function testWindowsDriveRelativeAndDrivelessPathsAreRefusedAgainstTheCurrentFolder(testCase)
assumeTrue(testCase, ispc, "Drive-relative and driveless-rooted forms exist only on Windows.");
for mode = ["canonical", "absolute"]
    verifyError(testCase, @() vawlume.internal.resolvePath("C:x\f.json", Mode=mode), ...
        "vawlume:internal:AmbiguousPath");
    verifyError(testCase, @() vawlume.internal.resolvePath("\x\f.json", Mode=mode), ...
        "vawlume:internal:AmbiguousPath");
end
% A UNC path is absolute, not driveless.
verifyTrue(testCase, vawlume.internal.resolvePath("\\server\share\f.json", Mode="isAbsolute"));
end

function testWithABaseADrivelessPathJoinsTheBaseAsTheOldSitesDid(testCase)
assumeTrue(testCase, ispc, "Drive-relative and driveless-rooted forms exist only on Windows.");
base = testCase.TestData.base;
verifyEqual(testCase, vawlume.internal.resolvePath("\a b\f.json", Base=base), ...
    string(fullfile(base, "a b", "f.json")));
verifyError(testCase, @() vawlume.internal.resolvePath("C:x\f.json", Base=base), ...
    "vawlume:internal:AmbiguousPath");
end

function value = canonical(path)
% Only ever called with an absolute path, so user.dir cannot affect it.
value = string(java.io.File(char(path)).getCanonicalPath());
end
