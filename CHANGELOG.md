# Changelog

## 0.2.0

- **⌘⌥V opens on your previous copy**, not the one ⌘V already pastes — so ⌘⌥V ⏎ now pastes the
  thing before last.
- **Copied images cost a fraction of the memory.** ClipIt no longer keeps the same picture two
  or three times over, and history now has a size budget as well as an item limit.
- Re-copying something already in history shows the fresh copy's time and source app instead of
  the original's.
- The mouse no longer steals the selection back while you're moving through history with the
  arrow keys.
- Updates install when you quit rather than restarting ClipIt mid-session, which used to clear
  your history without warning. When one is waiting, a small dot appears next to the menu bar
  icon and the menu reads **Quit and Update ClipIt** — no dialog, and nothing to dismiss.
- Install instructions now cover macOS 15 and later, where Apple removed the right-click → Open
  shortcut.

## 0.1.0

First release.

- Clipboard history in the menu bar: text, images and copied files, last 50 items.
- **⌘⇧V** pastes without formatting, leaving your clipboard's styled version intact.
- **⌘⌥V** opens a switcher next to your cursor; arrow keys to choose, Return to paste.
- List view and a wide card view with previews, toggled from either panel.
- Search across content, filenames and source app (**⌘F**).
- Memory-only: nothing is written to disk, and history clears when you quit or restart.
- Copies marked secret by password managers are never recorded.
