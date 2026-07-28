SwiftGibs for Mac — quick start
===============================

1. Unzip SwiftGibs-mac.zip (double-click it). You'll get SwiftGibs.app.

2. Move SwiftGibs.app to your Applications folder (optional, just tidy).

3. FIRST LAUNCH ONLY — right-click to open:
   Right-click (or Control-click) SwiftGibs.app  ->  Open  ->  Open again
   in the dialog that appears.

   Why: the app isn't signed with a paid Apple certificate, so a normal
   double-click makes macOS refuse it. The one-time right-click -> Open tells
   macOS you trust it. After that first time, a normal double-click works.

   If macOS still refuses (newer versions can be stricter):
   System Settings -> Privacy & Security -> scroll down ->
   click "Open Anyway" next to SwiftGibs, then launch it again.

4. Play. It's the same instagib SwiftGibs, and it joins the same
   servers. The server browser is filtered to instagib games; friends list,
   scoreboard columns, the reload countdown + metronome, the map-vote panel,
   and the flat team-colour player models are all included.

Updating
--------
When a new version comes out, update-swiftgibs.command (it ships right next
to SwiftGibs.app in the same download) fetches it for you:

1. FIRST USE ONLY - right-click to open: right-click (or Control-click)
   update-swiftgibs.command -> Open -> Open again in the dialog. Same
   one-time step as SwiftGibs.app itself, and only needed once, ever.
2. After that, just double-click update-swiftgibs.command any time. A
   Terminal window opens, downloads the latest release, and swaps in the new
   SwiftGibs.app. Close the window when it says done.
3. Your settings, friends and stats live in ~/Library/Application Support,
   not inside the app, so they're never touched by an update.
4. The updated SwiftGibs.app opens normally afterward, no second
   right-click needed - that ritual is only for apps downloaded straight
   through a browser.

Notes
-----
- Works on Apple Silicon (M1/M2/M3/M4). Built natively for it.
- Your settings save to ~/Library/Application Support/sauerbraten.
- To add friends so they're highlighted: F3 in-game opens the SwiftGibs menu,
  or use the friends menu; names are matched case-insensitively.

Have fun.
