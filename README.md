# Neco

An [oneko](https://ja.wikipedia.org/wiki/Oneko) / xneko-style desktop pet for
macOS. A cat lives in a small transparent, click-through window and chases your
mouse cursor. When it catches up it runs the original oneko idle chain (sit,
groom at a wall, paw, scratch, yawn, then curl up to sleep), and wakes with a
startle the moment the cursor moves.

Built with AppKit. Menu-bar only (no dock icon); a 🐱 menu-bar item provides
Pause/Resume and Quit.

## Sprites & license

Neco's own code is released under **CC0** (see `LICENSE`).

The cat sprites are the **public-domain oneko `neko` bitmaps**, converted from XBM
to embedded data in `Neco/Sprites.swift`.

- `xneko` by Masayuki Koba; `oneko` by Tatsuya Kato and others.
- Source: <http://www.daidouji.com/oneko/> (oneko-1.2.sakura.5, `bitmaps/neko/`).
- oneko / xneko are recognized as public domain by Debian, the FSF, and Fedora.

Not bundled on purpose: the BSD daemon bitmaps (Copyright 1988 Marshall Kirk
McKusick) and the Sakura / Tomoyo bitmaps (Cardcaptor Sakura characters, CLAMP /
Kodansha) that ship in the same tarball.
