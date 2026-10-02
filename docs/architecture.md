# Architecture

Hybrid DDD-lite, as described in [decision 0001](decisions/0001-architecture-style.md) (accepted). It has a pure Dart core with music logic and ports, a Flutter app built with MVVM and grouped by feature, and audio behind adapters. Solid boxes exist in the repository today. Dashed boxes are planned and have no code yet.

```mermaid
flowchart TD
    main["lib/main.dart<br/>entry point"]
    subgraph app["Flutter app (lib/)"]
        root["app/<br/>composition root, DI"]
        features["features/&lt;feature&gt;/<br/>views + view models"]
        shared["shared/<br/>widgets, theme"]
        repos["data/repositories/<br/>abstract, source of truth"]
        impl["data/repositories/impl/<br/>concrete repositories"]
        services["data/services/<br/>InstrumentFileStore"]
        audio["data/audio/<br/>PlaybackScheduler, SoLoud audition engine, WAV encoder"]
    end
    subgraph core["packages/synesterra_core (pure Dart)"]
        corePublic["synesterra_core.dart + src/core_identity.dart<br/>public entry point"]
        session["session/<br/>SessionDocument, parser and validation"]
        rhythm["rhythm/"]
        sound["sound/<br/>Instrument, renderer, EQ/envelope maths"]
        harmony["harmony/"]
        playback["playback/<br/>AudioTime, TempoMap, C0 generation"]
        ports["ports/<br/>AudioClock, VoiceSink"]
    end
    native["android/ + ios/<br/>native audio engine"]

    main --> root
    root --> features
    root --> impl
    features --> shared
    features --> repos
    impl --> repos
    impl --> services
    impl --> audio
    repos --> core
    audio --> playback
    audio -. "uses AudioClock, VoiceSink" .-> ports
    harmony --> rhythm
    session --> rhythm
    session --> harmony

    classDef planned stroke-dasharray: 5 5,fill:#f6f6f6,color:#333
    classDef exists fill:#dff3e4,color:#111
    class main exists
    class corePublic exists
    class root,features,shared,repos,impl,services,audio,session,rhythm,sound,harmony,playback,ports exists
    class native planned
```

Dependency rules R1–R9 and the real-time hand-off (who owns audio time, runtime state and stale-event cancellation) are in decision 0001; [architecture tests](modules/architecture-tests.md) enforce the import boundaries. In short:
- the core imports nothing from Flutter, plugins or I/O;
- features reach data only through abstract repositories;
- data never imports the UI;
- only `app/` imports concrete implementations.

The existing nodes above are backed by `lib/data/services/`, `lib/data/audio/`,
`packages/synesterra_core/lib/src/{sound,playback,ports,session,rhythm,harmony}/`,
`lib/features/`, `lib/shared/` and `lib/app/`. `android/` and `ios/` contain
Flutter-generated runner projects; no repository-owned native audio implementation
is present in them yet.

Update this diagram in the same PR that adds or moves a module; change the box style from planned to existing when code lands.
