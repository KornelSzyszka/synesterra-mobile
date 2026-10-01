# Architecture

Hybrid DDD-lite, as described in [decision 0001](decisions/0001-architecture-style.md) (accepted). It has a pure Dart core with music logic and ports, a Flutter app built with MVVM and grouped by feature, and native audio behind adapters. Solid boxes exist in the repository today. Dashed boxes are planned and have no code yet.

```mermaid
flowchart TD
    main["lib/main.dart<br/>Flutter template entry point"]
    subgraph app["Flutter app (lib/)"]
        root["app/<br/>composition root, DI"]
        features["features/&lt;feature&gt;/<br/>views + view models"]
        shared["shared/<br/>widgets, theme"]
        repos["data/repositories/<br/>abstract, source of truth"]
        impl["data/repositories/impl/<br/>concrete repositories"]
        services["data/services/<br/>stateless adapters"]
        audio["data/audio/<br/>PlaybackScheduler, engine bridge"]
    end
    subgraph core["packages/synesterra_core (pure Dart)"]
        session["session/<br/>SessionDocument, migration, SessionProject"]
        rhythm["rhythm/"]
        harmony["harmony/"]
        playback["playback/<br/>TempoMap, EventPlanner, runtime state"]
        ports["ports/<br/>AudioClock, VoiceSink, SessionStore"]
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
    audio -. "implements AudioClock, VoiceSink" .-> ports
    services -. "implements SessionStore" .-> ports
    audio <--> native
    harmony --> rhythm
    session --> rhythm
    session --> harmony
    playback --> session

    classDef planned stroke-dasharray: 5 5,fill:#f6f6f6,color:#333
    classDef exists fill:#dff3e4,color:#111
    class main exists
    class root,features,shared,repos,impl,services,audio,session,rhythm,harmony,playback,ports,native planned
```

Dependency rules R1–R9 and the real-time hand-off (who owns audio time, runtime state and stale-event cancellation) are in decision 0001; architecture tests will enforce the rules. In short:
- the core imports nothing from Flutter, plugins or I/O;
- features reach data only through abstract repositories;
- data never imports the UI;
- only `app/` imports concrete implementations.

`android/` and `ios/` exist as Flutter-generated runner projects; the native audio code in them is planned.

Update this diagram in the same PR that adds or moves a module; change the box style from planned to existing when code lands.
