# Keyboard event text after a layout switch

## Invariant

For physical keys in US, ABC, Russian, and RussianWin, Smart Input buffers text
translated from the hardware key code and the selected layout, including Shift
and Caps Lock. The session Event Tap's Unicode payload may still describe the
previous layout even after macOS confirms a switch. Arc can render the selected
layout while the tap reports the old script.

`KeyboardEventTextMap` builds immutable UCKeyTranslate tables on the main thread.
Layout IDs and their tables are published together under the input-context lock.
The Event Tap performs only a table lookup; it does not query TIS, Accessibility,
or synchronously dispatch to the main thread to translate ordinary keys.
Explicitly injected events, shortcuts, unsupported layouts/IMEs, and multi-character
text keep their original payload. LayoutPilot's own synthetic events retain their
existing bypass. This changes the internal buffer, not the incoming event.

## Regression and verification (2026-09-08)

Arc incident: `rfr` became `как`, `ыздше` became `split`; after the confirmed switch
to US, the next seven session events still reported Cyrillic. Arc displayed
`cltkfnm`, but Smart Input inferred Russian and skipped conversion at the space.

`KeyboardEventTextMapTests` exercises stale Russian payloads under US, confirms
`cltkfnm` converts to `сделать`, and checks the reverse direction, Shift, Caps Lock,
space, shortcut preservation, multi-character input, and unsupported IMEs.

Full suite: 124/125 pass. The existing
`testBilingualConversionCorrectsDoubleInitialUppercaseAfterTranslation` fails
(`XNj` -> `Что` returns nil); reproduced using the pre-fix SmartInputService too.
No user learning data was cleared to make this test pass.

Build/install: `./script/build_and_run.sh run` installs the signed Release build
at `/Applications/LayoutPilot.app`. Preserve the signing requirements in AGENTS.md.
Physical keyboard acceptance remains: in Arc, start with US and type the key
sequence intended as `как split сделать в arc`, allowing automatic switching.
Confirm the visible phrase and the trace action `physical_key_text_resolved` when
session Unicode differs. Unit tests are not proof of physical typing in Arc.
