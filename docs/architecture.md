# Architecture

Target module layout and dependency direction (`ui` depends on `audio`/`persistence`, which depend on `domain`; `domain` imports neither Flutter nor plugins). Solid boxes exist in the repository today; dashed boxes are planned and have no code yet.

```mermaid
flowchart TD
    subgraph app["App shell"]
        main["lib/main.dart<br/>Flutter template entry point"]
        boot["lib/app/<br/>bootstrap, DI, config"]
    end
    subgraph ui["Presentation"]
        screens["lib/ui/<br/>screens, widgets, UI state"]
        visual["lib/visual/<br/>visualization"]
    end
    subgraph platform["Platform services"]
        audio["lib/audio/<br/>transport clock, event planner, audio adapter"]
        native["android/ + ios/<br/>native audio, platform channels"]
        persist["lib/persistence/<br/>session storage"]
    end
    domain["lib/domain/<br/>pure Dart: session, rhythm, harmony"]

    main --> boot
    boot --> screens
    screens --> visual
    screens --> audio
    screens --> persist
    audio --> native
    audio --> domain
    persist --> domain
    visual -. "reads state, never drives transport" .-> audio

    classDef planned stroke-dasharray: 5 5,fill:#f6f6f6,color:#333
    classDef exists fill:#dff3e4,color:#111
    class main exists
    class boot,screens,visual,audio,native,persist,domain planned
```

`android/` and `ios/` exist as Flutter-generated runner projects; the native audio code in them is planned.

Update this diagram in the same PR that adds or moves a module; change the box style from planned to existing when code lands.
