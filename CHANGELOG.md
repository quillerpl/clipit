# Changelog

## 0.2.0

### Faster to the thing you actually want

- **⌘⌥V now opens on your previous copy**, not the newest one. The newest is what a plain ⌘V
  already pastes, so ⌘⌥V ⏎ gets you the thing before last in one go.

### Much lighter on memory

- **Copied images use a fraction of the memory they did**, with no change to how previews look.
  ClipIt was keeping the same picture up to three times over; now it keeps one copy and one
  preview.
- History has a size limit as well as a 50-item limit, so a run of big screenshots can't quietly
  fill your memory.

### Updates that don't cost you your history

- Updates now install **when you quit**, instead of restarting ClipIt mid-session and clearing
  everything you'd copied that day.
- When one is waiting, a small dot appears next to the menu bar icon and the menu reads **Quit
  and Update ClipIt**. No dialog, nothing to dismiss, and you pick the moment.

### Fixes

- Arrow keys work in the menu bar list. They previously did nothing but beep.
- Moving through history no longer jumps the list around. It now scrolls just far enough to
  bring the next item into view, in both list and card view.
- The mouse no longer steals the selection back while you're using the arrow keys.
- The menu bar list now matches the switcher and card drawer instead of looking lighter and
  flatter than both.
- Re-copying something already in your history shows the new copy's time and source app rather
  than the original's.

### Installing

- Install instructions now cover macOS 15 (Sequoia) and later, where the old right-click → Open
  step no longer works. Use **System Settings → Privacy & Security → Open Anyway** instead.

## 0.1.0

First release.

- Clipboard history in the menu bar: text, images and copied files, last 50 items.
- **⌘⇧V** pastes without formatting, leaving your clipboard's styled version intact.
- **⌘⌥V** opens a switcher next to your cursor; arrow keys to choose, Return to paste.
- List view and a wide card view with previews, toggled from either panel.
- Search across content, filenames and source app (**⌘F**).
- Memory-only: nothing is written to disk, and history clears when you quit or restart.
- Copies marked secret by password managers are never recorded.
