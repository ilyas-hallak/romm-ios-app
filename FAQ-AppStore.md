# Frequently Asked Questions

## Getting started

### What does this app do?

It is a client for your own RomM server.
It shows your library, lets you browse and search it, and downloads files from it to your device.

The five tabs are the whole app:

**Home** is your starting point, with recently added and recently opened entries from your server.
**Platforms** lists your systems, sorted, searchable and filterable.
**Collections** holds your own collections plus automatic ones like Favorites.
**Downloads** shows everything stored on this device, grouped by system, with how much space it takes.
**Search** looks through your whole library at once.

### Do I need a RomM server?

Yes.
RomM is a free, open source library manager that you host yourself, and this app is a mobile client for it.
Without a server there is nothing to show.

### Can I open a downloaded file in another app?

Yes.
Pick the app you already use under **Settings > Emulator App**, and a downloaded entry gets a button that hands the file to it.
You can also swipe an entry in the Downloads tab and use the normal iOS share sheet.

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
What fails is loading the entries of a single platform.

This is usually a reverse proxy cutting off a large response, or a server that is still scanning.
Try a platform with only a few entries.
If that one loads and a big one does not, the size of the response is the problem, and the proxy timeout or body limit is worth a look.

## Things you might not have found

### The same entry appears several times

Turn on **Group ROMs** in Settings and versions of the same title collapse into one entry.

If a title exists in several regions, open it and use the picker at the top to switch between the versions.

### Jumping through a long list

Long lists show an A to Z strip along the right edge.
Tap or drag it to jump straight to a letter.

### Some entries have a manual

If your server has a manual for an entry, its page gets a **Manual** tab that opens the PDF full screen.

### Getting a file off the device

Swipe an entry in the Downloads tab to share it, which opens the normal iOS share sheet, or to delete it and free up space.
