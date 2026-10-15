# References and methodological context

This page collects the primary publications for the external ultrasonic-vocalization (USV) extractors supported by VAWLUME and selected scientific background relevant to its multimodal workflow. The bibliography is intentionally selective rather than a survey of USV research.

**Scope of attribution.** VAWLUME is an independent, downstream integration and analysis framework. It imports outputs from supported extractors; it does not bundle, implement, run, or validate their detection algorithms. References to other research provide context and do **not** imply that VAWLUME reproduces those authors' methods or achieves their reported performance.

## Supported USV extractors

1. **DeepSqueak.** Coffey, K. R., Marx, R. E., & Neumaier, J. F. (2019). DeepSqueak: A deep learning-based system for detection and analysis of ultrasonic vocalizations. *Neuropsychopharmacology, 44*, 859–868. https://doi.org/10.1038/s41386-018-0303-6

2. **MUPET.** Van Segbroeck, M., Knoll, A. T., Levitt, P., & Narayanan, S. (2017). MUPET—Mouse Ultrasonic Profile ExTraction: A signal processing tool for rapid and unsupervised analysis of ultrasonic vocalizations. *Neuron, 94*(3), 465–485.e5. https://doi.org/10.1016/j.neuron.2017.04.005

3. **USVSEG.** Tachibana, R. O., Kanno, K., Okabe, S., Kobayasi, K. I., & Okanoya, K. (2020). USVSEG: A robust method for segmentation of ultrasonic vocalizations in rodents. *PLOS ONE, 15*(2), e0228907. https://doi.org/10.1371/journal.pone.0228907

These references credit the original extractor systems. VAWLUME's cross-extractor comparisons operate on their exported detection artifacts while preserving distinctions in native segmentation and measurement semantics; agreement among them should not be interpreted as independent ground truth.

## Caller-attribution research context

4. Neunuebel, J. P., Taylor, A. L., Arthur, B. J., & Egnor, S. E. R. (2015). Female mice ultrasonically interact with males during courtship displays. *eLife, 4*, e06203. https://doi.org/10.7554/eLife.06203

   This study illustrates the importance and difficulty of assigning vocalizations to individual animals during social interactions using acoustic localization together with video tracking. It is included as scientific context for VAWLUME's provenance-aware caller-attribution data model - not as a claim that VAWLUME implements the study's four-microphone localization algorithm. VAWLUME's present native two-microphone estimator is narrower and uncalibrated.

## Citation guidance

- **Using external extractor outputs:** Cite the publication(s) for the extractor(s) used to produce your data, as appropriate, independently of VAWLUME.
- **Using VAWLUME:** Until a formal release or DOI is available, please cite the repository and exact commit, as described in the [repository README](../README.md#citation).
- **Reporting analyses:** Describing the selected extractor versions, mapping profiles, matching specifications, alignment anchors/transform rules, and caller-attribution evidence or policies as appropriate is recommended.

No separate paper is listed here for routine relational storage, interval matching, or offset/affine clock transformations. Papers for planned sequence/bout analyses and future localization backends should be added when a specific implemented method makes them relevant. MATLAB, Database Toolbox, and SQLite are identified as dependencies in the repository documentation rather than treated as core scientific references.
