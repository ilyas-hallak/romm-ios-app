# Frequently Asked Questions

## Getting started

### What does this app do?

It is a client for your own RomM server.
It shows your game library, lets you download games to your device, and plays them right here.

The five tabs are the whole app:

**Home** is your starting point, with the games you played last and the ones recently added to the server.
**Platforms** lists your systems, sorted, searchable and filterable.
**Collections** holds your own collections plus automatic ones like Favorites.
**Downloads** shows everything stored on this device, grouped by system, with how much space it takes.
**Search** looks through your whole library at once.

### How do I play games in the app?

Open **Settings** and turn on **In-App Emulator**.
It is off until you do, and the play options stay hidden until then.

This section only exists in TestFlight builds.
The App Store version has no emulator at all, so if you are looking for it there, that is why you cannot find it.

### Which systems can I play?

Game Boy, Game Boy Color, Game Boy Advance, NES, SNES, Nintendo DS, Nintendo 64, Sega Genesis, PlayStation and PC Engine.

### PlayStation games ask for a BIOS

PlayStation emulation needs the original BIOS files, which cannot ship with the app.
Go to **Settings > BIOS Files** and download them from your server, provided you put them there.

## Connecting to your server

### I can sign in from Safari, but the app says "Invalid username or password"

This is the most common report by far, and there are three usual causes.

**Your server uses OIDC or SSO.**
Tap **Sign in with Browser** on the setup screen instead of typing a password.
Your account has no local RomM password in that case, so username and password can only fail.
The browser handles the sign-in and you approve the app from there.

**Something sits in front of RomM and asks for a login first.**
Authelia, Cloudflare Access and similar gatekeepers show their own page in a browser, and the app never sees it.
It just gets rejected.
Either exempt the RomM API from that gatekeeper, or reach the server on a route that skips it.

**Your password manager pasted a trailing space.**
Type the password by hand once to rule that out.

### The app cannot reach my server, but the browser can

Enter the address with `http://` or `https://` in front.
The app does not add it for you, and without it the address is rejected before any connection is attempted.

Include the port if your server uses one, for example `http://192.168.1.50:8080`.

For a local IP address, iOS asks for permission to find devices on your network the first time.
Deny it and every connection fails while the browser keeps working, because the browser has its own permission.
You can grant it later under **Settings > RomM > Local Network**.

### It says my server version is not supported

The app supports RomM **4.1.0 through 5.2.0**.

Outside that range you can still continue: the setup screen offers to sign in anyway.
Expect the odd rough edge, since a newer server may answer in ways this version of the app does not know yet.

### I signed in, but tapping a platform shows "Network connection error"

The login succeeded and the app can see your library, so the address and credentials are fine.
What fails is loading the games of a single platform.

This is usually a reverse proxy cutting off a large response, or a server that is still scanning.
Try a platform with only a few games.
If that one loads and a big one does not, the size of the response is the problem, and the proxy timeout or body limit is worth a look.

## Playing games

### There is no Play button, only Download

Games are played from your device, not streamed from the server, so a game has to be downloaded once before it can start.
After the download finishes, the Play button appears in the same place.

You can also start any downloaded game from the **Downloads** tab.

### I start a game and get asked about save states

That dialog appears when the game already has save states.
Pick one to continue where you left off, or start a new game and leave them untouched.
Without save states the game just starts.

### Which emulator engine should I use?

The app picks one for you, and in most cases that is the right answer.

The **native** engine runs on your device and is the faster, better integrated one, with save states, controller support and controller skins.
The **web** engine runs the emulator your server ships and needs a connection while you play.

You can force one under **Settings > Emulator Engine**.

### The on-screen buttons cover the game

Connect a physical controller and the on-screen skin disappears on its own.
While it is hidden you can drag the game up and down with one finger to place it where you want it, and set its size in the in-game menu.

### Can I play on my TV?

Yes.
Connect the phone to a TV, by cable or screen mirroring, and **Play on TV** appears in the in-game menu.

The game then renders at the TV's resolution instead of being a mirrored phone screen.
You can also dim the phone while playing, which saves battery and is nicer in a dark room.

## Save games

### What is the difference between a save and a save state?

A **save** is what the game itself writes when you save inside it, on the cartridge so to speak.
It survives everything and is the one the game knows about.

A **save state** is a snapshot of the emulator, taken at any moment, and it comes back exactly as it was.
There are 21 slots per game, numbered 0 to 20.
Slot 0 is a normal slot like any other, there is nothing special about it.

Use saves for real progress and save states for the tricky passage you would rather not repeat.

### I overwrote the wrong save state

Open the in-game menu and use **Undo Save**.
It puts back what was in the slot before.

There is an **Undo Load** as well, for when you loaded a state and lost what you were doing.

### Are my saves synced with the server?

Not unless you turn it on.
Cloud sync is off by default and can be enabled in **Settings**.

With it on, saves are pulled before a game starts and pushed back afterwards, so the same game continues on another device.

### Can I use my saves with RetroArch or another emulator?

Saves are stored as `.sav`.
Some emulators, including the mGBA core in RetroArch, expect `.srm` instead.
The contents are the same, so renaming the file works.

## Controllers

### How do I open the in-game menu with a controller connected?

Set a shortcut first, it is off by default.
Go to **Settings > Emulator Engine > Menu shortcut** and pick either **L3 + R3** (press both sticks) or **L1 + R1** (both shoulder buttons).
That combination then opens the menu while you play.

Without a shortcut the menu is only reachable by touch, which is awkward once the phone sits in a controller.

### My controller is connected but the game does not react

On iPad, a connected Bluetooth keyboard can keep the game from listening to the gamepad.
Disconnect the keyboard and try again.

### The buttons are in the wrong place

If your controller uses the Nintendo layout, where A and B are swapped compared to Xbox, turn on the face button swap under **Settings > Emulator Engine**.

### Can I change how the on-screen controls look?

Yes, the native engine takes Delta controller skins.
Go to **Settings > Controller Skins** and import one from a file or a URL, then pick it per system.
A new skin applies the next time you start a game.

## Things you might not have found

### The same game appears several times

Turn on **Group ROMs** in Settings and versions of the same game collapse into one entry.

If a game exists in several regions, open it and use the picker at the top to switch between the USA, European and Japanese version.

### Jumping through a long list

Lists with many games show an A to Z strip along the right edge.
Tap or drag it to jump straight to a letter.

### Some games have a manual

If your server has a manual for a game, the game's page gets a **Manual** tab that opens the PDF full screen.

### Getting a game off the device

Swipe a game in the Downloads tab to share it, which opens the normal iOS share sheet, or to delete it and free up space.
