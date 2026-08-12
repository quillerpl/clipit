# ClipIt Sync — design

Cross-device clipboard sync over the local network, and a Windows client at feature parity
with the macOS app.

**Status:** design only. Nothing here is built yet.

---

## What changes about ClipIt

Today's README opens with *"nothing it records ever leaves your Mac — or even touches your
disk."* Sync breaks both halves, and the honest version becomes:

- Clipboard content **crosses the local network**, encrypted, to devices you have explicitly
  paired.
- Pairing keys **must be written to disk** (Keychain on macOS, DPAPI on Windows) or you would
  re-pair after every restart.

Clipboard *history* stays in memory. Nothing goes to a cloud service, and there is no account.
The privacy section needs rewriting before this ships, not after.

Two things that must survive unchanged:

- Anything a password manager marks as secret is **never captured, and therefore never
  synced**. macOS uses `org.nspasteboard.ConcealedType`; Windows has
  `ExcludeClipboardContentFromMonitorProcessing` and `CanIncludeInClipboardHistory`. Both must
  be honoured before an item enters the store.
- Sync is **opt-in per device pair**. An unpaired ClipIt behaves exactly as it does today.

---

## Shape

```
┌────────────────────┐        Noise-encrypted TCP        ┌────────────────────┐
│   macOS (Swift)    │◄─────────────────────────────────►│  Windows (C#)      │
│   SwiftUI panels   │                                   │  WinUI 3 panels    │
├────────────────────┤                                   ├────────────────────┤
│         clipit-core (Rust, one implementation, C ABI)  │                    │
│  discovery · pairing · crypto · framing · sync state   │                    │
└────────────────────┴───────────────────────────────────┴────────────────────┘
```

`clipit-core` owns everything security-critical and everything protocol-shaped. Each platform
owns only what it must: reading and writing its own clipboard, its own UI, its own hotkeys.

The split matters most for the crypto. Written twice, it gets subtly different twice.

### FFI

The core exposes a deliberately tiny C ABI — roughly: start, stop, pair, unpair, announce a
local clip, fetch a remote clip, plus one event callback carrying a CBOR payload. Keeping the
surface small is what makes two bindings tolerable.

- **Swift** consumes it as an `.xcframework` binary target (universal: arm64 + x86_64).
- **C#** consumes it via `[LibraryImport]` source-generated P/Invoke (x64 + arm64).

---

## Discovery

DNS-SD over mDNS: `_clipit._tcp.local`, TXT carrying protocol version, device name and a device
ID (hash of the device's static public key).

Using the `mdns-sd` Rust crate rather than each platform's own stack — Windows has no
dependable built-in mDNS responder, and Bonjour-for-Windows is not something to make users
install.

**mDNS fails often enough that a fallback is mandatory, not optional.** Guest Wi-Fi with client
isolation, VPNs, corporate networks and some mesh routers all block it. There must be a
"connect by IP address" path in the UI from day one.

---

## Pairing

Uses the [Noise Protocol Framework](https://noiseprotocol.org) (`snow` crate) rather than TLS —
mutual authentication from raw static keys, no certificate machinery to build on two platforms.

**First pairing** — `Noise_XX`, which exchanges static keys:

1. On device A: *Add a device*. It becomes pairable for two minutes.
2. Device B sees A in a list and selects it.
3. Both devices derive a **6-digit code from the handshake hash** and display it.
4. The user confirms the codes match, and the pairing completes.

That last step is what prevents a machine-in-the-middle. The code is not a password typed into
one device — it is a fingerprint of the negotiated session, shown on both. If an attacker sat
in the middle, the two codes would differ.

**Every session after that** — `Noise_KK`, where both static keys are already known. No
verification step, no MITM window at all.

Trust store: peer static key, device name and pairing date, in the Keychain / DPAPI.

---

## Sync protocol

Length-prefixed CBOR frames inside the Noise transport.

| Message | Purpose |
|---|---|
| `Hello` | Version, device ID, name, capabilities |
| `ClipAnnounce` | Metadata for a new clip: id, kinds, hashes, sizes, origin, timestamp, small inline preview |
| `ClipRequest` | "Send me kind X of clip Y" |
| `ClipData` | Chunked payload |
| `Ping` / `Pong` | Liveness |

### Announce, then fetch

Clips are announced as metadata first, not pushed whole. A naive "broadcast everything" design
stalls the moment you copy an 8 MB screenshot.

- **Text under ~256 KB** rides along inline in the announce. It arrives instantly, which is
  what makes automatic mirroring feel right.
- **Anything larger** is announced with a thumbnail and fetched on demand.

### Promised data — the important trick

You chose automatic mirroring: copy on the Mac, press Ctrl+V on Windows, it is there. But
eagerly transferring every screenshot and file across the network the instant it is copied is
wasteful, and most copies are never pasted on the other machine.

Both operating systems support putting a **promise** on the clipboard instead of the bytes:

- macOS: `NSPasteboardItemDataProvider` supplies data lazily when something asks for it.
- Windows: delayed rendering — the app receives `WM_RENDERFORMAT` when a paste actually occurs.

So a large remote clip is mirrored as a promise. The bytes cross the network **at the moment
you paste**, not at the moment you copy. Files work the same way: on paste, stream into a temp
directory and hand the OS a path — which also neatly sidesteps the two machines having
completely different directory layouts.

The cost is honest and worth stating: pasting a large item has visible latency, and it fails if
the other machine has gone to sleep. Mitigation is a size threshold — below roughly 2 MB,
transfer eagerly; above it, promise — plus a clear error rather than a silent empty paste.

### Loops

Every clip carries `clipId = hash(content)` and an origin device ID. Applying a remote clip
locally adds its id to a suppression set, so the local clipboard watcher doesn't observe the
change and announce it straight back. The macOS app already does exactly this for its own
pastes (`suppressCurrentChange`); this generalises it.

---

## Clipboard format mapping

The fiddly, unglamorous part, and the one most likely to produce "why did my formatting
break" bug reports.

| Meaning | macOS UTI | Windows format | Notes |
|---|---|---|---|
| Plain text | `public.utf8-plain-text` | `CF_UNICODETEXT` | Line endings: LF ↔ CRLF |
| Rich text | `public.rtf` | `CF_RTF` (registered) | Broadly compatible |
| HTML | `public.html` | `CF_HTML` (registered) | Windows wraps it in a byte-offset header that must be generated and parsed |
| PNG | `public.png` | `"PNG"` (registered) | Preferred image path |
| Bitmap | `public.tiff` | `CF_DIBV5` | Fallback; alpha handling differs |
| Files | `public.file-url` | `CF_HDROP` | Paths are meaningless across machines — files always transfer as content |

Conversion lives in the core, with round-trip test vectors, so both platforms agree.

---

## The Windows app

.NET 8 + **WinUI 3**, chosen for native Mica/Acrylic backdrops — matching ClipIt's translucent
panels in WPF would mean hand-rolling them.

| Concern | macOS today | Windows equivalent |
|---|---|---|
| Watch clipboard | Poll `changeCount` | `AddClipboardFormatListener` → `WM_CLIPBOARDUPDATE` (event-driven, better) |
| Global hotkeys | Carbon `RegisterEventHotKey` | `RegisterHotKey` |
| Synthesize paste | `CGEvent` + Accessibility permission | `SendInput` — **no permission needed** |
| Find the caret | Accessibility API | UI Automation `TextPattern`, or `GetGUIThreadInfo` |
| Menu bar / tray | `NSStatusItem` | `NotifyIcon` |
| Launch at login | `SMAppService` | Registry `Run` key or Startup Task |

Shortcuts become Ctrl+Shift+V and Ctrl+Alt+V.

**Windows' own Win+V will still be there.** Two clipboard histories side by side is confusing,
so the app should offer to turn Windows' one off during setup, and explain why.

**Distribution has the same problem as macOS.** Unsigned Windows apps trigger SmartScreen, and
an OV code-signing certificate is a few hundred dollars a year. Same shape of decision as
notarization.

---

## Phases

Each phase ends somewhere usable rather than half-built.

| # | Deliverable | Why here |
|---|---|---|
| 0 | Protocol spec, Rust core skeleton, crypto and format tests. No UI. | Get the part that is hard to change right, first |
| 1 | **Mac ↔ Mac text sync.** Pairing UI, discovery, mirroring. | Proves core, FFI and pairing without a second OS in the mix |
| 2 | Windows client: capture, history, tray, hotkeys, paste. | The functional half of parity |
| 3 | Windows UI parity: panels, switcher, cards, search. | The visual half |
| 4 | Images, with promises and thresholds. | Needs a working two-platform pipeline to test properly |
| 5 | Files. | Highest complexity, lowest frequency |
| 6 | Hardening: reconnection, >2 devices, manual IP, diagnostics. | Informed by real use |

Phase 1 is the honest checkpoint. If pairing and mirroring don't feel good between two Macs,
they will not feel better with Windows added.

---

## Risks

**Automatic mirroring is surprising.** Your clipboard changes without you touching it, so the
thing you copied ten seconds ago can vanish exactly as you go to paste it. Planned mitigations:
a brief HUD when a remote clip arrives so it is never silent; a pause toggle; and never
overwriting a local copy made in the last few seconds. Worth re-testing in phase 1 — if it
still grates, the fallback is history-only with a shortcut to pull the newest remote item.

**mDNS is unreliable** on exactly the networks people use. Manual IP entry from day one.

**Two clipboard managers on Windows** — see above.

**Signing costs on both platforms** if this is to be installable by non-technical people.

**Scale.** The Windows parity port alone is comparable to everything built for macOS so far.
The phasing exists so there is something working long before the end.

---

## Open questions

- How many devices realistically — two, or a small mesh? Two is simpler and the protocol can
  stay pairwise; a mesh needs conflict ordering.
- Should sync pause automatically on untrusted networks (e.g. only sync on known Wi-Fi)?
- Does the Windows app need the ⌘⌥V caret-anchored switcher, or is the tray panel enough?
  UI Automation caret positioning is materially less reliable than the macOS Accessibility API.
