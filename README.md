# Neco [![CI](https://github.com/winebarrel/Neco/actions/workflows/ci.yml/badge.svg)](https://github.com/winebarrel/Neco/actions/workflows/ci.yml) [![AI Generated](https://img.shields.io/badge/AI%20Generated-Claude-orange?logo=anthropic)](https://claude.ai/claude-code)

An [oneko](https://ja.wikipedia.org/wiki/Oneko) / xneko-style desktop pet for
macOS. A cat lives in a small transparent, click-through window and chases your
mouse cursor. When it catches up it runs the original oneko idle chain (sit,
groom at a wall, paw, scratch, yawn, then curl up to sleep), and wakes with a
startle the moment the cursor moves.

![](https://github.com/user-attachments/assets/cb183bd7-a0a9-4e2e-8dd6-93cdfd647b92)

![](https://github.com/user-attachments/assets/0dc1e861-aa9e-4584-9619-24eab0a889e9)

Built with AppKit. Menu-bar only (no dock icon); a 🐱 menu-bar item provides
Pause/Resume and Quit.

## Sprites & license

Neco's own code is released under **CC0** (see `LICENSE`).

The cat sprites are the **public-domain oneko `neko` bitmaps**, converted from XBM
to embedded data in `Neco/Sprites.swift`. The cat has a history worth keeping:

- The cat was drawn by **Juan Gotoh (後藤寿庵)** for *neko DA*, a Macintosh desk
  accessory. The design is his original.
- **Masayuki Koba (古場正行)** turned it into the bitmaps for the X11 program
  *xneko* (1990).
- **Tatsuya Kato** derived *oneko* from xneko, reusing its cat bitmaps almost
  unchanged.

Gotoh, Koba, and Kato each confirmed the artwork and program are free to use,
modify, and redistribute; oneko / xneko are treated as public domain by Debian,
the FSF, and Fedora.

- Provenance: <https://www.3bit.co.jp/~sasaki/oneko/COPYRIGHTS>.
- Bitmap source: <http://www.daidouji.com/oneko/> (oneko-1.2.sakura.5, `bitmaps/neko/`).

Not bundled on purpose: the BSD daemon bitmaps (Copyright 1988 Marshall Kirk
McKusick) and the Sakura / Tomoyo bitmaps (Cardcaptor Sakura characters, CLAMP /
Kodansha) that ship in the same tarball.

## Related links

- [Neko: History of a Software Pet | Eliot Akira](https://eliotakira.com/neko/)
