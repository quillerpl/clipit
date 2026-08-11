<div align="center">

# ClipIt

**Everything you copy, one keystroke away.**

A clipboard history for macOS that lives in your menu bar.
Nothing it records ever leaves your Mac — or even touches your disk.

</div>

---

## Install

1. Download **ClipIt.dmg** from [Releases](https://github.com/quillerpl/clipit/releases/latest).
2. Open it and drag **ClipIt** to **Applications**.
3. Open Applications and **right-click ClipIt → Open**, then click **Open** in the dialog.

> **Why right-click the first time?** ClipIt isn't signed with a paid Apple developer
> certificate, so macOS shows an "unidentified developer" warning on first launch. Right-click →
> Open is how you tell macOS you trust it. You only do this once. Double-clicking instead of
> right-clicking will just show a warning with no way past it.

ClipIt then walks you through the one permission it needs.

### The permission

macOS requires **Accessibility** access before *any* app can paste on your behalf — pasting
means pressing ⌘V for you, and macOS treats that as controlling your computer. ClipIt asks
for nothing else: no network, no files, no contacts.

Recording your clipboard works without it. Only pasting is blocked.

---

## What it does

| | |
|---|---|
| **⌘⇧V** | Paste **without formatting**. Strips fonts, sizes and colours; your clipboard keeps the styled version so a normal ⌘V still works. |
| **⌘⌥V** | A small panel opens **next to your cursor** with your last few copies. `←` `→` to choose, `⏎` to paste, `esc` to close. Drag it aside if it's in the way. |
| **Menu bar icon** | The full history — text, images and files, with search. |

Holds your last 50 copies. Text keeps its formatting, images and copied files show real
previews.

### Keys

| Key | Does |
|---|---|
| `↑` `↓` | Move through the list |
| `1`–`9` | Paste that row |
| `⏎` | Paste the selected item |
| `⇧⏎` | Paste it as plain text |
| `⌘F` | Search |
| `esc` | Close |
| `⌘1`–`⌘9` | Paste that card (card view only) |

Switch between **list** and **card** view with the toggle at the top-left of either panel.

---

## Privacy

- **Nothing is written to disk.** History lives in memory. Quitting ClipIt or restarting your
  Mac clears it completely — the same way Windows' clipboard history behaves.
- **Nothing is sent anywhere.** ClipIt has no network code beyond checking for its own updates.
- **Password managers are skipped.** Anything 1Password, Bitwarden or KeePassXC marks as a
  secret is never recorded.

---

## Building from source

Requires macOS 14+ and Xcode 16.

```bash
git clone https://github.com/quillerpl/clipit.git
cd clipit
./make-signing-cert.sh   # one-time; see "Accessibility keeps re-asking" below
./build.sh               # builds, installs to /Applications, launches
```

```bash
swift test               # 47 tests
./release.sh             # universal build + DMG + signed update feed
```

`release.sh --notarize` additionally submits to Apple, which removes the right-click-to-open
step for everyone. It needs the paid Apple Developer Program plus `CODESIGN_IDENTITY` and
`NOTARY_PROFILE` — see the header of [release.sh](release.sh).

### Layout

```
Sources/ClipItKit/       everything: capture, paste, hotkeys, panels
  ClipboardMonitor.swift    changeCount polling + capture rules
  ClipboardStore.swift      in-memory history, dedupe, search
  ClipboardItem.swift       one snapshot: representations, thumbnail, display strings
  Paster.swift              pasteboard writes, focus restore, synthesized ⌘V
  HotKeyManager.swift       Carbon RegisterEventHotKey wrapper
  CaretLocator.swift        finds the insertion point via the Accessibility API
  IconRenderer.swift        draws the app icon at every size
  Views/                    history list, card drawer, switcher, welcome
Sources/ClipIt/          thin executable shell
Tests/ClipItKitTests/    capture rules, store, search, layout maths
```

The library/executable split exists so the tests can reach the code — testing an executable
target directly is fragile across toolchains.

---

## Accessibility keeps re-asking, or the switch is on but nothing pastes

This is the one genuinely confusing failure mode, and it is macOS's doing.

macOS ties the Accessibility grant to an app's **code signature**. An ad-hoc signature gets a
new hash on every build, so after rebuilding, the System Settings switch stays visibly ON while
the app is actually denied.

- `make-signing-cert.sh` creates a self-signed `ClipIt Dev` certificate (trusted **for code
  signing only**, not as a general root), giving the app one stable identity so the grant
  sticks. Nothing here asks for your password.
- `build.sh` installs to `/Applications` deliberately: this project lives on an external volume
  mounted `noowners`, where TCC grants are unreliable.

To see what macOS actually thinks, rather than trusting the switch:

```bash
/Applications/ClipIt.app/Contents/MacOS/ClipIt --check-trust
```

If it prints `false` while the switch is on, remove ClipIt from the Accessibility list with
**–**, then re-add it with **+**.

**Greyed out in the Accessibility file picker?** Either it's already in the list (the picker
disables apps that are), or the bundle isn't registered with LaunchServices — `cp` doesn't do
that. `build.sh` runs `lsregister`; by hand it's:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/ClipIt.app
```

---

## Deliberate choices

**Memory-only.** History is never persisted. Sleep does *not* clear it — the app keeps running
across sleep, and wiping on every screen-off would make the feature useless.

**⌘⇧V is taken over globally.** Several apps use it for "Paste and Match Style"; ClipIt's
version does the same thing, and adds it to apps that lack it. To change it, edit
`registerHotKeys()` in [AppDelegate.swift](Sources/ClipItKit/AppDelegate.swift).

**Carbon hotkeys, not a CGEventTap.** `RegisterEventHotKey` needs no permission, so the
shortcuts work the moment you launch, before you've been to System Settings.

**No ⌘N shortcuts in the ⌘⌥V switcher.** It floats over another app that still owns most of the
keyboard, so ⌘2 there would reach that app and switch its tab instead. The card drawer is a key
window and does consume them, so it keeps its badges.

---

## Gotchas worth knowing before you change things

**"Copy Image" outranks its own URL.** Browsers put an image *and* its source URL on the
pasteboard. An entry with bitmap data plus nothing but a bare URL is classified as an image —
otherwise a copied picture shows up as a link.

**Copied image files need Quick Look.** Copying a photo in Finder puts a file URL on the
pasteboard, not a bitmap. `requestQuickLookThumbnail()` fetches a real preview asynchronously,
which is why `ClipboardItem` is an `ObservableObject`.

**Panels read `visibleItems`, never `items`.** Otherwise the search filter desynchronises the
rows from the ⌘N indices and ⌘3 pastes the wrong thing.

**Dimmed text needs explicit opacities.** SwiftUI's `.secondary`/`.tertiary` are tuned for
opaque windows and wash out over a translucent one.

**`isMovableByWindowBackground` isn't enough** to drag a SwiftUI-hosted panel — the hosting view
swallows the mouseDown. `WindowDragHandle` forwards it to `performDrag`.

**The paste waits for you to let go.** The hotkey fires while ⌘⇧ are still held, so posting ⌘V
immediately would land as ⌘⇧V and re-trigger the app.

**Hardened runtime is only enabled for Developer ID builds.** It turns on library validation,
which requires every loaded framework to share the host's Team ID — a self-signed certificate
has none, so embedded Sparkle would fail to load at launch.

---

## Licence

[MIT](LICENSE).
