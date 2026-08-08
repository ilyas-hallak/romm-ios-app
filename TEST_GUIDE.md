# Test Guide — test/all-fixes (6 changes)

Build & run this branch on your device (monk) via Xcode, then check each item:

## 1. ZIP download (#34)
Download a ROM that lives inside a folder on the server (or a PSX title the server serves as a zip). It should launch directly — no more manually adding `.zip` to the file.

## 2. Cloud save states (#33)
Open a ROM that already has old server save states with non-`slotN` names (e.g. `Chrono Trigger (USA) [2026-...]`). Open the emulator's Save/Load State menu — the pre-existing states should now show up, not just newly created ones.

## 3. Detail page network error (#35)
Open detail pages of several games, especially ones with sparse metadata (no developer/company). The developer/console header should load without a "Network connection error".

## 4. Game card border (#36)
Browse the home/library grid, especially a game with a wide/panoramic cover. The cover should stay clipped inside its card, every card has a visible border, and nothing bleeds into neighbouring cards.

## 5. Haptics on release (#37)
In a Libretro (PSX) game, press and release on-screen buttons — you should feel a lighter haptic on release too. Check the in-game menu for a "Release Haptics" toggle; turning it off should stop the release haptic.

## 6. Screen position (#38)
Settings → Emulator engine settings → "Screen Position" (Center / Top). Set to Top and launch a Libretro (PSX) game — the video should pin to the top. Set back to Center — video centered. (Libretro/PSX only; native/Delta frontend unaffected.)

---
Note: none of the 6 PRs were compiler-verified individually. If the build fails, check the merge for that area first.
