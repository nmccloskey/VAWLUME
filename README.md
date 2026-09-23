# VAWLUME

**Vocalization Analysis Workflow Liaison Using MATLAB Extensions**

> **Status: research prototype.** VAWLUME is a working prototype published for transparency and reuse, not a released or scientifically validated tool. Its schema, configuration contracts, and `vawlume.*` API may change substantially. Numeric thresholds shipped with the prototype are illustrative demonstration values unless explicitly documented otherwise.

VAWLUME is a MATLAB-centered, relational framework for making independent vocalization analyses interoperable without collapsing their disagreement. It maps heterogeneous extractor, project, and multimodal data into a provenance-aware SQLite model so detections and derived evidence can be compared, aligned, attributed, and explored while preserving how they were originally produced.

VAWLUME does **not** detect vocalizations itself. DeepSqueak, MUPET, and USVSEG are external integrations whose outputs VAWLUME reads and relates.

## Goals

The prototype is organized around six linked goals:

1. **Relational ingestion** of USV extractor outputs and other experimental data.
2. **Extractor consilience exploration and data-validation support** without treating extractor agreement as ground truth.
3. **Multimodal temporal alignment** onto auditable common timebases.
4. **Caller-attribution support** for representing and relating localization, tracking, identity, acoustic, and imported attribution evidence.
5. **Incorporating sequence and bout analysis**, with grouping semantics kept explicit rather than assumed from extractor-native labels.
6. **Niche EDA** for the above workflows, including agreement topology, feature disagreement, threshold sensitivity, and multimodal context.

See the [prototype overview](docs/prototype/00_overview.md) for the current scope, design principles, implementation status, and boundaries.

## Current prototype

Implemented today are provenance-aware source mapping and project intake; DeepSqueak, MUPET, and USVSEG import; pairwise and arbitrary-N cross-extractor correspondence and agreement; consilience summaries and independent manual-reference evaluation; anchor-based temporal alignment; multimodal spatial/tracking/acoustic-reference intake; imported caller-attribution representation; consilience-oriented exploratory analysis; and relational CSV export.

The extractor-consilience workflow has run end to end on one real Pilot 3 recording containing DeepSqueak, MUPET, and USVSEG outputs. That demonstrates operational execution on real imported data, **not scientific validation**: comprehensive manually reviewed ground truth and threshold calibration have not been completed.

Sequence/bout analysis remains a stated goal rather than an implemented workflow. A VAWLUME-native caller estimator is also future work; the current attribution path represents multimodal evidence and imported attribution claims without inventing a combined caller-confidence score.

## Requirements

| Requirement | Detail |
|---|---|
| MATLAB | R2026a — the release currently used for testing |
| Database Toolbox | Supplies MATLAB's `sqlite` connection object |
| External extractors | Not required to run the demos; required only to generate real extractor artifacts for import |

Development and testing have been carried out on Windows 11. Cross-platform support is not yet claimed.

## Quick start

From the repository root:

```matlab
openProject("VAWLUME.prj")   % or: addpath("src")
addpath("examples")

matching_consensus_demo          % pairwise correspondence + consilience
multi_extractor_agreement_demo   % arbitrary-N agreement
multimodal_integration_demo      % geometry, tracking, identity, acoustic response
caller_attribution_demo          % imported caller-attribution path
consilience_exploration_demo     % consilience-oriented EDA
csv_export_demo                  % relational CSV export
```

The examples create disposable synthetic inputs and require no data of your own. For setup, configuration, tests, importing real data, and detailed examples, use the [prototype usage guide](docs/prototype/01_usage_guide.md).

## Documentation

- **[Prototype overview](docs/prototype/00_overview.md)** — goals, niche, architecture, current implementation, design principles, and prototype boundaries.
- **[Prototype usage guide](docs/prototype/01_usage_guide.md)** — setup, configuration, end-to-end workflows, real-data use, outputs, testing, and troubleshooting.
- **[Interactive database ERD](https://liambx.com/erd/p/github.com/nmccloskey/VAWLUME/blob/main/schema/schema.json?format=tbls)** — browse the relational model generated from VAWLUME's SQLite schema.
- [`schema/README.md`](schema/README.md) — schema authority, regeneration, and ERD notes.
- [`docs/design/`](docs/design/) — design contracts and forward-looking architecture.
- [`docs/development/`](docs/development/) — implementation contracts, boundaries, and completed development work.
- [`docs/reference/extractors/`](docs/reference/extractors/) — extractor-specific mapping references.

## Supported extractor integrations

The prototype currently includes adapters and mapping profiles for:

- [DeepSqueak](https://github.com/DrCoffey/DeepSqueak)
- [MUPET](https://github.com/mvansegbroeck/mupet)
- [USVSEG](https://github.com/rtachi-lab/usvseg)

These are **integrations, not components**. VAWLUME contains none of their code and does not wrap or invoke them. Their native artifacts and semantics remain attributable to their respective projects and authors.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Nicholas McCloskey.

The VAWLUME license does not extend to MATLAB or external extractor software.

## Citation

VAWLUME is currently an unpublished research prototype with no DOI. If you use it, cite the repository and exact commit used, for example:

```text
McCloskey, N. (2026). VAWLUME: Vocalization Analysis Workflow Liaison Using
MATLAB Extensions (prototype, commit <short-hash>) [Computer software].
https://github.com/nmccloskey/VAWLUME
```

Please do not cite the prototype as a released or scientifically validated tool.
