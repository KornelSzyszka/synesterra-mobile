# Instrument pad (superseded)

The circular dot pad (issues #83, #107) was replaced by the [instrument radar](instrument-radar.md) in UX-115 (issue #115, Founder 2026-10-13). Its code (`instrument_pad.dart`, `instrument_pad_view.dart`, `pad_geometry.dart`) and tests were removed. The five characters (`warm drone`, `airy pad`, `bass`, `guitar`, `click`) live on as radar presets ([instrument, Traits](../modules/instrument.md#traits)); instruments saved from the pad are ordinary recipes and open on the radar as an approximation. The rules and anchor values are in this file's git history.
