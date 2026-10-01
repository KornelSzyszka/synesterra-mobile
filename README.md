# synesterra-mobile
Standalone Flutter/Dart app for Synesterra on Android and iOS.

This repository is reserved for the native mobile app. The existing TypeScript web/PWA laboratory lives in [synesterra-web](https://github.com/KornelSzyszka/synesterra-web).

Current status: Flutter scaffold and CI only. The app logic and physical-device audio validation have not started yet.

## Architecture

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

Quality gates: format, analyze, test and a debug APK build run in [CI](.github/workflows/ci.yml); iOS is built on demand. Emulator runs and unit tests do not prove audio timing or behaviour on a physical phone.

Agent collaboration rules and model routing: [docs/agents](docs/agents/README.md).
