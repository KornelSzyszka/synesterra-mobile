# Architecture

Hybrid DDD-lite, as described in [decision 0001](decisions/0001-architecture-style.md) (proposed). It has a pure Dart core with music logic and ports, a Flutter app built with MVVM and grouped by feature, and native audio behind adapters. Solid boxes exist in the repository today. Dashed boxes are planned and have no code yet.

```mermaid
flowchart TD
    main["lib/main.dart<br/>Flutter template entry point"]
    subgraph app["Flutter app (lib/)"]
        root["app/<br/>composition root, DI"]
        features["features/&lt;feature&gt;/<br/>views + view models"]
        shared["shared/<br/>widgets, theme"]
        repos["data/repositories/<br/>source of truth"]
        services["data/services/<br/>platform adapters"]
    end
    subgraph core["packages/synesterra_core (pure Dart)"]
        session["session/<br/>SessionDocument, migration, SessionProject"]
        rhythm["rhythm/"]
        harmony["harmony/"]
        playback["playback/<br/>EventPlanner, runtime state"]
        ports["ports/<br/>AudioClock, VoiceSink, SessionStore"]
    end
    native["android/ + ios/<br/>native audio engine"]

    main --> root
    root --> features
    root --> repos
    root --> services
    features --> shared
    features --> repos
    repos --> services
    repos --> core
    services -. implements .-> ports
    services --> native
    harmony --> rhythm
    session --> rhythm
    session --> harmony
    playback --> session

    classDef planned stroke-dasharray: 5 5,fill:#f6f6f6,color:#333
    classDef exists fill:#dff3e4,color:#111
    class main exists
    class root,features,shared,repos,services,session,rhythm,harmony,playback,ports,native planned
```

Dependency rules R1–R8 are listed in decision 0001 and will be enforced by architecture tests. In short:
- the core imports nothing from Flutter, plugins or I/O;
- features never import each other or platform services;
- data never imports the UI;
- only `app/` wires concrete implementations.

`android/` and `ios/` exist as Flutter-generated runner projects; the native audio code in them is planned.

Update this diagram in the same PR that adds or moves a module; change the box style from planned to existing when code lands.
