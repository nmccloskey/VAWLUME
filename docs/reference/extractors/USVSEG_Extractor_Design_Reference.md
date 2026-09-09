# VAWLUME Extractor Design Reference: USVSEG

**Purpose:** Establish the factual USVSEG import contract underlying VAWLUME's
built-in USVSEG output mapping profile, in enough detail that every mapping can
be audited without reopening the upstream investigation.
**Prepared:** 2026-09-09
**Primary software scope reviewed:** `usvseg09r2.m` from the official
`rtachi-lab/usvseg` MATLAB repository, plus the repository readme and the
peer-reviewed method paper.
**Implemented profile:**
[`config/01_mapping_profiles/extractors/usvseg/usvseg_output_mapping_profile.json`](../../../config/01_mapping_profiles/extractors/usvseg/usvseg_output_mapping_profile.json)
**Status:** Working design reference. The shipped JSON profile, not this
document, is authoritative for VAWLUME behavior. Update both together if VAWLUME
adds support for another USVSEG version or the Python port.

---

## 1. Evidence conventions

Every factual claim below is one of three kinds, and they are never blended:

- **[SOURCE]** — read directly from `usvseg09r2.m`.
- **[DOC]** — stated by the repository readme or the method paper.
- **[VAWLUME]** — a VAWLUME policy or interpretation, not a claim about USVSEG.
- **[OPEN]** — genuinely unresolved without a representative artifact, and
  therefore deliberately not mapped.

Where a fact could be mistaken for a USVSEG guarantee it is stated as what
VAWLUME requires instead.

---

## 2. Software identity and version scope

USVSEG is a GUI-based MATLAB script for robust segmentation of rodent ultrasonic
vocalizations. **[DOC]**

- Repository: `https://github.com/rtachi-lab/usvseg`, MIT licensed. **[DOC]**
- The repository ships several single-file revisions — `usvseg08r6.m`,
  `usvseg08r7.m`, `usvseg09r2.m`. The latest is `usvseg09r2.m`. **[DOC]**
- The application identifies itself as **"USVSEG ver 0.9 (rev 2)"** in its figure
  window title, and **writes no version string into any output file**. **[SOURCE]**
- A Python port exists (`MatsumotoJ/usvseg_python`). It is out of scope for this
  profile and would need its own version scope if ever supported. **[DOC]**

**Profile version scope:** `preferred = "0.9r2"`, verified against
`usvseg09r2.m`.

### Consequence: version cannot be recovered from output

Because no artifact carries a version, the caller must declare it. The profile
sets `extractor.version_required_at_ingest = true`, matching the MUPET pattern
rather than any attempt at inference. **[VAWLUME]**

USVSEG also has no workspace, dataset, project, or session concept. A VAWLUME
extraction run is a caller declaration anchored to a recording and a version, not
a structure recovered from the output tree. **[VAWLUME]**

---

## 3. Output inventory

One segmentation pass over one WAV file can produce: **[SOURCE]** **[DOC]**

| Output | Emitted | VAWLUME role |
|---|---|---|
| `<stem>_dat.csv` — per-syllable summary table | always | **primary event export** |
| `<stem>/<stem>_NNNN.csv` — per-syllable spectral peak trace | when trace output is enabled | optional artifact, event-scoped lineage |
| `<stem>/…​.wav` — segmented syllable audio | when WAV output is enabled | optional derived-audio artifact |
| `<stem>/…​.jpg` or `.tif` — spectrogram images | when image output is enabled | optional figure artifact |
| `usvseg_prm.mat` — saved parameter structure | on application close | optional, weak settings evidence |

Auxiliary outputs go into a subfolder created inside the input folder and named
after the recording stem. The summary CSV is offered beside the source WAV as
`<stem>_dat.csv`, through a save dialog the user can redirect. **[SOURCE]**

Only the summary CSV is ingested as detections in the prototype. The others are
registered as artifacts so their existence and provenance survive, without
inventing a second event population. **[VAWLUME]**

---

## 4. The summary CSV contract

This is the exact and complete contract for the primary event export. **[SOURCE]**

**Header — one line, no other comment lines:**

```text
#,start,end,duration,maxfreq,maxamp,meanfreq,cvfreq
```

**Row format:** `%d,%.04f,%.04f,%.1f,%.03f,%.02f,%.03f,%.04f`

| Column | Source expression | Unit | Meaning |
|---|---|---|---|
| `#` | syllable ordinal `n` | — | 1-based index within the pass |
| `start` | `onoffset(n,1)` | **s** | onset, absolute in the recording |
| `end` | `onoffset(n,2)` | **s** | offset, absolute in the recording |
| `duration` | `dur(n)*1000` where `dur = diff(onoffset,[],2)` | **ms** | offset minus onset |
| `maxfreq` | `maxfreq(n)/1000` | **kHz** | peak frequency of the highest-amplitude frame |
| `maxamp` | `maxampval(n)` | **dB** | multitaper-spectrogram amplitude at that peak |
| `meanfreq` | `meanfreq(n)/1000` | **kHz** | mean of the primary peak-frequency trace |
| `cvfreq` | `std/mean` of that trace | ratio | coefficient of variation of the trace |

Three unit conversions are needed and all three transforms already exist in the
registry: `identity`, `ms_to_s`, `kHz_to_Hz`. **No new transform key is
required.** **[VAWLUME]**

### 4.1 The identifier column is literally `#`

The header's first field is the single character `#`. A default MATLAB table
reader rewrites that into a generated variable name, which would break
`source_field` resolution. The profile therefore declares
`native_processing_notes.event_table_header.reader_requirement =
"preserve_original_column_names"` and a matching validation check. The reader
built in pass 1.3 must honor it. **[VAWLUME]**

### 4.2 Times are absolute

Audio is processed in blocks, and per-block onsets are shifted by the elapsed
block time before export, so exported times are absolute from the start of the
recording rather than block-relative. **[SOURCE]**

### 4.3 Duration is redundant with start and end

`duration` is exactly the printed onset/offset difference, so it carries no
information the boundaries lack. VAWLUME preserves it as a native measurement —
discarding a value the extractor reported would violate the native-preservation
rule — but the boundaries remain the timing authority. **[VAWLUME]**

The two print precisions differ: boundaries at four decimal seconds (0.1 ms),
duration at one decimal millisecond. A duration-consistency check must therefore
allow combined print rounding rather than demand exact equality. This is a
milder version of the MUPET situation, where the two durations are genuinely
different quantities; here they are the same quantity printed twice. **[VAWLUME]**

### 4.4 A zero-detection run still writes a CSV

When no syllables are found the file is written with the header row and no data
rows. **[SOURCE]** That is a valid result — an extraction run with zero
detections — and must not be treated as a failed or empty export. **[VAWLUME]**

---

## 5. Event identity

`#` is a 1-based ordinal assigned within one segmentation pass and continued
across that pass's internal read blocks. **[SOURCE]**

Re-running USVSEG renumbers from 1, so the value identifies an event only within
its own extraction run and artifact. The profile scopes
`native_event_id` to `recording` + `event_export_artifact` and sets
`stable_cross_artifact_identifier = false`, matching MUPET's syllable
number. **[VAWLUME]**

One nuance worth recording: within a single run, the four-digit index in a trace
or segment filename equals that syllable's `#`. **[SOURCE]** That makes those
files event-scoped lineage for the same run — not an independent identifier
system, and not stable across runs.

---

## 6. Feature semantics and cross-extractor comparability

USVSEG exports three acoustic features plus one variability measure. Each is
mapped to the narrowest defensible canonical construct.

### 6.1 `maxfreq` → `peak_frequency`

The peak frequency of the time frame with the highest amplitude in the
syllable. **[DOC]** **[SOURCE]** This is precisely the existing canonical
`peak_frequency` construct — "frequency associated with peak event power or
amplitude" — and shares `vocalization_peak_frequency` with DeepSqueak's
`Peak Freq (kHz)`. MUPET exports no counterpart.

### 6.2 `meanfreq` → `frequency_center`, and why that is not equivalence

The mean of the primary tracked peak frequency over the syllable's
frames. **[SOURCE]** It shares the `vocalization_frequency_center` equivalence
class with MUPET mean frequency and DeepSqueak principal frequency, and is
method-equivalent to neither:

| Extractor | Central-frequency construct |
|---|---|
| USVSEG | mean of a discrete tracked peak-frequency series |
| MUPET | mean over a filterbank representation |
| DeepSqueak | median of a derived contour |

Three different operations on three different intermediate representations. The
shared equivalence class makes the pairs **discoverable** for deliberate review.
It does not make them comparable — that still requires an explicitly registered
eligible feature relationship, which pass 1.2 must decide on evidence rather than
inherit from this placement. The existing regression coverage already asserts
exactly this distinction for central frequency. **[VAWLUME]**

### 6.3 `maxamp` → `peak_amplitude`, ineligible by default

`maxampval(n)` indexes the **multitaper spectrogram**, defined in source as
`20*log10((spmat/ntapers)*sqrt(1/(2*pi*fftsize)))`. **[SOURCE]** So:

- the unit is dB;
- the reference level is an arbitrary internal scale;
- it is read from the unflattened spectrogram, not the flattened one the
  threshold is computed on.

It shares `vocalization_amplitude_like_quantity` with MUPET's peak syllable
amplitude and is not comparable to it — no shared zero, no common calibration.
`consilience_role` is `none_by_default`, consistent with the standing rule that
power, energy, and amplitude quantities stay ineligible. **[VAWLUME]**

### 6.4 `cvfreq` → new canonical `frequency_cv`

The standard deviation of the primary peak-frequency trace divided by its
mean. **[SOURCE]** Dimensionless and mean-normalized.

This is **not** DeepSqueak's `Frequency Standard Deviation (kHz)`, which is an
absolute spread in frequency units mapped to `frequency_sd` /
`vocalization_frequency_sd`. Putting a normalized ratio and an absolute spread in
one equivalence class would be exactly the false equation the conservative
feature rules exist to prevent.

The profile therefore introduces `canonical_field = "frequency_cv"` and
`equivalence_class = "vocalization_frequency_cv"`. Both are new to the shipped
vocabulary and require a deliberate registration decision in pass 1.2. **[VAWLUME]**

### 6.5 What USVSEG does not export

Not exported, and not derivable from what is: **[SOURCE]**

`frequency_min`, `frequency_max`, `frequency_bandwidth`, `frequency_slope`,
detection score, curation state, class or manual label, inter-event interval.

The profile records these as absent and declares
`no_synthesized_frequency_bounds` as an **error**-severity check. USVSEG
consequently cannot participate in frequency-extent comparisons at all. That is a
real limitation of the extractor, not a gap in the mapping. **[VAWLUME]**

The optional trace files do contain per-frame frequencies from which a min and a
max could be computed — which is exactly why the prohibition is explicit. A
VAWLUME-computed extremum of a peak track is not the same construct as a
DeepSqueak or MUPET frequency bound, and fabricating one would silently create a
comparison that no extractor supports.

---

## 7. Settings evidence: available but weak

`usvseg_prm.mat` holds a `prm` structure containing `fftsize`, `timestep`,
`freqmin`, `freqmax`, `threshval`, `durmin`, `durmax`, `gapmin`, `margin`,
`readsize`, `wavfileoutput`, `imageoutput`, `imagetype`, `traceoutput`, `mapL`,
`mapH`. **[SOURCE]**

Two properties decide the policy: **[SOURCE]**

1. It is written **when the application closes**, holding whatever parameters
   were active at that moment.
2. It is a **single application-scoped file**, not written beside the CSV it may
   or may not correspond to.

So it is not per-run provenance. It cannot be trusted to describe the run that
produced a given CSV.

### Policy decision

**Settings are optional for apply** — the DeepSqueak pattern, not the MUPET one.
**[VAWLUME]**

Requiring them would refuse ordinary, correct USVSEG output, because USVSEG never
writes run-scoped settings beside its event export. The Phase 0 carry-forward
rule said absence of settings evidence should not by itself block import "unless
upstream behavior proves a stronger requirement"; upstream behavior here proves
the opposite.

When a `usvseg_prm.mat` is supplied it is recorded with its artifact identity and
an explicit `evidence_strength = "weak_not_run_scoped"` marker, never as the
verified configuration of the run.

### Documented defaults are reference values, not observations

The reviewed version's defaults are `timestep` 0.0005 s, `freqmin` 30 kHz,
`freqmax` 120 kHz, `threshval` 4.5 SD, `durmin` 5 ms, `durmax` 300 ms, `gapmin`
30 ms, `margin` 15 ms, with `fftsize` fixed at 512 and not user-editable.
**[SOURCE]** The method paper gives working ranges of 3.5–5.5 for the threshold
and 3–30 ms for the minimum gap, both species-dependent. **[DOC]**

None of these may be written into a run's settings record. A default is a
contextual reference value, not evidence about any particular
run. **[VAWLUME]**

Note also that `threshval` is a multiple of the estimated background-noise
standard deviation, not an absolute level — two runs with the same `threshval`
on different recordings did not use the same effective threshold. **[SOURCE]**

---

## 8. Review and classification evidence: none

USVSEG exports no curation flag, no accept/reject state, no class assignment, and
no manual label. It is a segmenter, not a classifier or a review tool. **[SOURCE]**

The profile declares this absence positively — `exports_no_curation_state` and
`exports_no_native_class_or_manual_label` — and adds an **error**-severity
`no_unsupported_annotation_evidence` check. An unexpected column of that kind
means the artifact is not what this profile describes; the adapter must reject it
rather than silently discard extractor evidence. This mirrors the guard MUPET's
import path already applies. **[VAWLUME]**

---

## 9. Recording linkage

USVSEG writes no reference to its input file inside any output. The only link is
the naming convention: `<stem>.wav` → `<stem>_dat.csv` and a `<stem>/` auxiliary
folder. **[SOURCE]**

Preferred resolution order is therefore source-audio checksum, persistent VAWLUME
recording id, relative path and stem, then filename as a weak fallback — the same
ladder the other extractors use, with checksum preferred precisely because the
stem correspondence is only a convention. **[VAWLUME]**

---

## 10. Mapping audit table

Every column, its canonical target, and its comparability status in one place.

| CSV column | Native unit | Canonical field | Canonical unit | Transform | Equivalence class | Default consilience role |
|---|---|---|---|---|---|---|
| `#` | — | `native_event_id` | — | — | — (identifier) | n/a |
| `start` | s | `call_start_time` | s | `identity` | `vocalization_start_time` | primary |
| `end` | s | `call_end_time` | s | `identity` | `vocalization_end_time` | primary |
| `duration` | ms | `call_duration` | s | `ms_to_s` | `vocalization_duration` | primary or supporting |
| `maxfreq` | kHz | `peak_frequency` | Hz | `kHz_to_Hz` | `vocalization_peak_frequency` | supporting |
| `maxamp` | dB | `peak_amplitude` | dB | `identity` | `vocalization_amplitude_like_quantity` | none by default |
| `meanfreq` | kHz | `frequency_center` | Hz | `kHz_to_Hz` | `vocalization_frequency_center` | supporting |
| `cvfreq` | ratio | `frequency_cv` **(new)** | ratio | `identity` | `vocalization_frequency_cv` **(new)** | none by default |

Seven event-measurement mappings plus one event identifier — eight mappings for
eight columns, with nothing dropped and nothing invented.

---

## 11. Consequences for later passes

- **Pass 1.2 (registration).** One new canonical feature name, `frequency_cv`,
  falls outside the current name-keyed canonical-feature description switch and
  would otherwise register under domain `other`. It needs an explicit arm, as do
  the USVSEG extractor description and repository entries — their generic
  fallbacks are conflict-checked on every later registration, so they must land
  with the profile path, not after it. Registering this profile should add one
  config profile, one profile version, one extractor, one extractor version,
  seven extractor features, seven feature mappings, and one canonical feature.
  Those deltas are a prediction from this profile's contents, to be verified
  against the seed test rather than assumed.
- **Pass 1.3 (reader).** Must preserve original column names so `#` resolves, and
  must treat a header-only file as a valid zero-detection table.
- **Pass 1.4 (import).** Must enforce the caller-supplied version, the optional
  settings policy, and the annotation-absence guard.
- **Pass 1.5 (matching).** USVSEG participates in ordinary pairwise temporal
  matching on start and end. It cannot participate in frequency-extent
  comparisons at all, and its central-frequency and amplitude features need
  deliberate eligibility decisions before any feature agreement uses them.

---

## 12. Open items

Genuinely unresolved without a representative USVSEG artifact, and therefore
deliberately not mapped: **[OPEN]**

1. **Non-finite tokens.** The exporter prints every column unconditionally with a
   numeric format and declares no missing-value sentinel, so the profile declares
   no `missing_value_policy`. The internal mean and standard deviation both omit
   NaNs, which makes a non-finite `meanfreq` or `cvfreq` unlikely but not
   provably impossible for a degenerate single-frame syllable. The profile
   surfaces this through a warning-severity `numeric_column_completeness` check
   instead of guessing either answer. Settle it in pass 1.3 against a real file.
2. **Save-dialog relocation.** The summary CSV path is user-redirectable, so the
   stem-based recording linkage can be weakened by an unusual save location. The
   discovery regex matches `<stem>_dat.csv` anywhere; whether real workflows
   relocate it is unknown.
3. **Locale and delimiter.** The writer emits comma-separated output with a
   period decimal separator unconditionally. Whether any user workflow
   post-processes this into another delimiter is unknown and out of contract.

None of these blocks the profile. Each is a detail the reader pass can settle
cheaply once a representative file exists.

---

## 13. Sources reviewed

- Official MATLAB repository and readme: `https://github.com/rtachi-lab/usvseg`
- Source inspected: `usvseg09r2.m` (CSV writer, `segfun`, `specpeaktracking`,
  parameter save path, output naming and folder creation)
- Tachibana RO, Kanno K, Okabe S, Kobayasi KI, Okanoya K (2020). USVSEG: A robust
  method for segmentation of ultrasonic vocalizations in rodents. *PLOS ONE*
  15(2): e0228907.
- Author resource page: `https://sites.google.com/view/rtachi/resources`
- Python port, noted but not in scope: `https://github.com/MatsumotoJ/usvseg_python`
