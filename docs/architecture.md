# Architecture

## Bounded contexts

### Learning Mode

Owns rehearsal semantics: a loop range, rest duration, playback speed, and a
calibrated eight-count grid. The grid is defined by two taps: where the first
eight starts and where it ends. Every later beat is derived from that interval.

### A+B Analysis

Owns two editable tracks, their trim windows, independent speeds, shared scrub
progress, and output intent. It does not know which media engine performs the
eventual render.

### Music Practice

Owns audio/video input semantics, original-versus-stem selection, the six
HTDemucs stem identities, and music-loop behavior. Its ports describe media
preparation, separation, and selected-stem mixing without importing Flutter,
FFmpeg, ONNX Runtime, or audio-player APIs.

### Shared Video Playback

Contains only genuinely shared vocabulary (`VideoSource`, `PlaybackRate`,
`TimeRange`). It is deliberately small and is not a generic dumping ground.

## Dependency direction

```text
entrypoints/mobile -> application -> domain
        |                                ^
        +--------> infrastructure -------+
```

Domain objects import neither Flutter nor device plugins. UI controllers translate
plugin state into feature commands. Infrastructure owns file picking, cameras,
video/audio playback, FFmpeg composition, on-demand model storage, and local
ONNX inference.

## Export decision

An `AnalysisExporter` port carries an `AnalysisExportRequest`; its FFmpeg adapter
renders either B or the side-by-side A+B canvas. Music Practice similarly keeps
FFmpeg preparation/mixing and HTDemucs ONNX inference behind feature ports.

## Suggested milestones

1. Validate Learning Mode timing and camera ergonomics on physical iOS/Android.
2. Persist projects and recent videos locally.
3. Implement composition/export with progress, cancellation, and background work.
4. Add waveform/frame thumbnails and linked/unlinked A+B playback.
5. Add integration tests and device performance budgets.
