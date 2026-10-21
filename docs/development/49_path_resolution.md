# 49. Path resolution has one home

`vawlume.internal.resolvePath` is the one function that turns a path into an
absolute filesystem location. Built at itinerary 7.11, promoted from the CSV
export's `exportResolvePath`. Contract 07 D14 is the design. It is not user API.

```matlab
p  = vawlume.internal.resolvePath(value);                  % against pwd
p  = vawlume.internal.resolvePath(value, Base=repoRoot);   % against a named base
p  = vawlume.internal.resolvePath(value, Mode="absolute"); % no canonicalization
tf = vawlume.internal.resolvePath(value, Mode="isAbsolute");
```

## The defect it removes

`java.io.File` resolves a relative path against the JVM's `user.dir`. That is
fixed when Java starts, and MATLAB's `cd` never moves it. MATLAB's own file
functions resolve against `pwd`, so after any `cd` the two disagree and a
relative path can silently name a different file. The CSV export measured
this in Part 7. In `-batch` the JVM starts lazily, so `user.dir` is whatever
`pwd` was at the first Java call.

The helper never hands a relative path to Java. It joins it to an explicit
base first: `pwd` by default, or `Base=`. A relative base is itself resolved
against `pwd`.

## Modes

| Mode | Result |
|---|---|
| `"canonical"` (default) | absolute, then `getCanonicalPath`: `.` and `..` removed, links the host resolves for Java resolved |
| `"absolute"` | absolute, then `getAbsolutePath`: separators normalized, nothing else |
| `"isAbsolute"` | `java.io.File.isAbsolute` as a logical. Nothing is resolved or refused |

No case folding in any mode.

## Windows forms that are refused

These raise `vawlume:internal:AmbiguousPath`:

- **Drive-relative** (`C:data\x`): refused always.
- **Driveless-rooted** (`\data\x`): refused when resolving against `pwd`.
  With `Base=` it is joined to the base, as every base-relative site did
  before 7.11. This keeps every input those sites resolved unchanged.

`exportResolvePath` is a thin wrapper that re-raises the refusal as
`vawlume:export:AmbiguousPath`.

## Each site keeps its own base

Most loaders resolve a profile path against `RepoRoot`, not `pwd`, and they
still do. A loader's sequence is unchanged: test with `Mode="isAbsolute"`,
join with `fullfile(repoRoot, …)`, then canonicalize through the helper. Only
where a site was literally "if relative, join, canonicalize" with no fallback
does it call `Base=` directly:

- `registerProfileVersion` (`content_path`);
- `attributionIntakeSourcePath`.

Sites that caught a canonicalization failure and fell back to the raw text
still do. A refused form therefore falls back to the raw text, which MATLAB
then reads against `pwd`.

## Documented wrappers

These local or private functions now only call the helper. A guard searching
for `java.io.File(...).isAbsolute` or `getCanonicalPath` outside the home
(closure invariant 54) finds none of them:

- `exportResolvePath`;
- `alignmentCanonicalPath` and `alignmentIsAbsolutePath` (`+ingest/private`);
- each package's local `canonicalPath`, `normalizePath`, `normalizedPath`,
  `resolveRepoRoot` and `isAbsolutePath`.

`buildIntegratedFixture` opens one file with `java.io.FileOutputStream`. Its
path now comes from the helper (`Mode="absolute"`), so Java writes where
MATLAB wrote.

## Not here

The helper resolves paths for opening and for deriving identities. It does
not decide what is **stored**. The stored text of `path_or_uri`,
`content_uri`, `relative_path` and artifact paths is unchanged by 7.11.

The portable-root policy (alignment R7) and manifest ownership (R5) are
deferred beyond v2 (D14). An inventory of which resolved paths are stored and
which are only opened is in the 7.11 handoff, for R7's owner.

`readAudioWindow`'s own `isAbsolutePath` is a regex, not the idiom. It treats
`/x` as absolute on Windows, where Java does not. Changing it would change
which stored `path_or_uri` values need `SourceRoot`, so it is left as it was.
