# Acoustic-reference registration and provenance

VAWLUME represents an acoustic reference as a claim that a point or interval in
a recording's native audio clock contains a useful known signal. The claim is
stored in `acoustic_references`; it is not a measurement of channel response and
it is not a synchronization anchor.

## Representation

Each row names one `recording_id`, a stable `reference_key`, an open-text
`reference_type`, and inclusive start/end times in native audio seconds. Equal
times are a point-like reference. A row may apply to every recording channel or
cite one `recording_channel_id`; schema triggers reject a channel owned by a
different recording on both insert and update.

Optional fields preserve:

- a source-native label;
- either or both frequency bounds in Hz;
- a linked imported `external_event_id`;
- source file, source locator, and mapping-profile version;
- notes.

Frequency bounds are metadata about the claimed signal, not observed spectral
measurements. Neither bound is required. Supplied bounds must be nonnegative,
and the maximum cannot be below the minimum.

The external-event link is provenance only. A trigger requires the event's
stream to belong to the same recording. No row in `alignment_anchors` or
`alignment_anchor_observations` is created or implied. If one physical tone is
used for both purposes, the user declares the two independent objects.

## Registration

`vawlume.acoustic.registerReference` accepts a recording selector and a scalar
reference specification:

```matlab
recordingRef = struct(recording_id=12);
spec = struct( ...
    reference_key="low-tone-01", ...
    reference_type="tone", ...
    native_label="LOW_TONE", ...
    start_time_s=15, ...
    end_time_s=17, ...
    channel_index=1, ...
    frequency_min_hz=18000, ...
    frequency_max_hz=22000, ...
    source_file_id=31, ...
    mapping_profile_version_id=9, ...
    source_locator="references.csv:row:4");
result = vawlume.acoustic.registerReference(conn, recordingRef, spec);
```

Omitting `channel_index` declares a recording-wide reference. Registration is
idempotent by `(recording, reference_key)`: identical content is reused and
changed content raises `vawlume:acoustic:ReferenceConflict`. Native recordings,
events, and audio are never changed.

When `mapping_profile_version_id` is supplied, it must identify an
`external_stream_mapping` profile. Phase 2.5 deliberately introduced no
`acoustic_reference_mapping` profile kind: the existing mapper already supports
intervals, arbitrary native/normalized labels, typed attributes, and source-row
provenance. The shipped
`config/01_mapping_profiles/external_streams/acoustic_reference_event_mapping_profile.json`
shows tone, noise, optional frequency fields, optional channel index, and an
unmapped user-defined label. Its database-free IR can feed registration without
a vendor or behavioral-controller parser.

## Reading

`vawlume.acoustic.readReferences` returns reference identity, channel scope,
optional band, and source/profile/event provenance:

```matlab
allRows = vawlume.acoustic.readReferences(conn, recordingRef);
channelRows = vawlume.acoustic.readReferences(conn, recordingRef, ...
    ChannelIndex=1);
windowRows = vawlume.acoustic.readReferences(conn, recordingRef, ...
    ChannelIndex=1, StartTimeS=10, EndTimeS=20);
```

A channel filter returns both channel-specific rows and recording-wide rows that
apply to that channel. Window filters use interval overlap. The recording-native
timebase declaration is returned when one exists; its absence remains missing.
A linked external event's stream/timebase fields are separate columns, so source
event provenance cannot masquerade as the reference's timing authority.

## Deliberate boundary

This layer reads no audio samples and computes no power, amplitude, response,
normalization factor, or correction. Those are derived products owned by later
Phase 2 work. No caller-attribution concept appears in the table or API.
