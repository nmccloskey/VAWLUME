# USVSEG export adapter

`vawlume.ingest.usvsegExport` is the database-free boundary between one
USVSEG 0.9r2 primary event export and VAWLUME's shared extractor-output IR:

```matlab
export = vawlume.ingest.usvsegExport(csvPath, ...
    RepoRoot=repoRoot, ExtractorVersion="0.9r2");
preview = vawlume.source_mapping.preview(export.ir);
```

The adapter reads only the profile-selected `usvseg_dat_csv` artifact. It does
not wrap or run USVSEG, import optional trace/WAV/image outputs, infer an
extractor version, or access SQLite. Database registration of the extraction
run and detections is a separate later boundary.

## File contract

The shipped profile declares a comma-separated `<stem>_dat.csv` with the
literal header:

```text
#,start,end,duration,maxfreq,maxamp,meanfreq,cvfreq
```

The reader preserves every variable name, including `#`, and imports every
cell as a string before source mapping. This keeps the exact printed token
recoverable while the profile-driven mapper performs numeric typing and unit
transforms. A token such as `NA` is therefore not silently converted to a
missing value: the profile declares no USVSEG sentinel, so the token remains
visible and typed mapping reports an error. A parseable non-finite token such
as `Inf` remains visible and produces the profile-required adapter warning.

A file containing the header and no data rows is valid and produces one mapped
source with zero event records and zero values. A zero-byte file is unreadable.
The file extension, profile-declared delimiter and header mechanics, distinct
source labels, and portable relative-path rules are guarded explicitly. The
adapter accepts an explicitly supplied relocated CSV without trying to
rediscover it from its filename.

## Mapping and provenance

The adapter contains no native-to-canonical field dictionary. It passes the
preserved table to `vawlume.source_mapping.mapTableToIR`, which obtains required
fields, canonical names, units, transforms, operational definitions, and
missing-value policy from the tracked USVSEG profile.

The result includes:

- `ir`: validated shared extractor-output IR;
- `table`: the complete lexical source table;
- `artifact`: checksum, portable/runtime location, file mechanics, source
  columns, and row/column counts;
- `profile` and `profile_document`: mapping-profile identity and declarations;
- `extractor_version`: comparison of caller-supplied evidence to profile scope;
- `issues`: adapter-level version and numeric-completeness diagnostics.

Unknown source columns remain in `result.table` exactly as read. The shared
mapper also emits `SOURCE_COLUMN_UNMAPPED` according to the profile's
`preserve_and_warn` policy. The current IR does not yet materialize per-row
unknown values into the schema's `unmapped_source_values`; retaining the full
source table keeps those values recoverable for that later database importer.

## Version behavior

USVSEG outputs carry no version string. `ExtractorVersion` is therefore caller
evidence. `0.9r2` matches the shipped profile's preferred scope. A missing or
incompatible declaration remains explicit in `extractor_version` and produces
an adapter warning during database-free inspection; the later database-facing
importer is responsible for enforcing the profile's required-at-ingest policy.

The factual format and semantic evidence behind this contract is documented in
[`../reference/extractors/USVSEG_Extractor_Design_Reference.md`](../reference/extractors/USVSEG_Extractor_Design_Reference.md).
