# Local insta server

A local instagib FFA server that boots straight into **fdm6** with **instant
respawns**: the server force-respawns dead players itself about 300ms after
death (the engine's hit-event flush window) - no clicking, no waiting.

Stock protocol 260, so any SwiftGibs or Sauerbraten 2020 client can join.
Follows the mapbattle-testserver pattern: a scratch build tree under /tmp gets
the standard SwiftGibs patches plus `local-insta-server.patch`, which adds four
server cvars (none shipped in any bundle):

- `defaultmap` / `defaultmode` - map+mode loaded at boot and re-loaded whenever
  the server empties (fresh match every visit)
- `autospawn` - 1 = server respawns dead players itself (players who just
  joined or just loaded a map still self-spawn the vanilla way)
- `autospawndelay` - extra ms of death-cam on top of the 300ms flush window,
  if truly-instant ever feels too abrupt

## Run it

    tools/local-insta-server/run-server.sh

UDP 28785, unlisted, no password, `maxclients 8`. Config is `server-init.cfg`
in this directory (the server's home dir). First run after a reboot rebuilds
the /tmp tree; later runs are quick.

## Join it

    /connect <WSL IP>

run-server.sh prints the exact command with the current IP when it starts.
From Windows, `/connect localhost` does NOT work: NAT-mode WSL only forwards
TCP over localhost, not UDP (verified 2026-08-05 - a UDP probe to
localhost:28786 from the Windows side gets port-unreachable while the WSL IP
answers). The WSL IP changes across reboots, hence the banner. Clients carry
their own maps, so the server needs no map files.

## Playing with friends on the same WiFi

The WSL server above is reachable only from this machine. A WSL-hosted server
cannot be exposed to the LAN at all: NAT-mode WSL does not forward UDP, and
Windows `netsh portproxy` (what the Minecraft setup uses) is TCP-only.

So for LAN games, build a native Windows server instead:

    tools/local-insta-server/make-windows-server.sh

That cross-compiles `sauer_server.exe` with mingw and drops it on the Windows
desktop with its config and launcher. Run `run-server.bat`: it prints both
connect addresses, and the first time it asks for admin to add one Windows
Firewall rule (inbound UDP 28785-28786). The rule is required - this WiFi is
classified "Public", where Windows blocks inbound traffic by default. If the
admin prompt gets missed, right-click `allow-firewall.bat` and pick "Run as
administrator" instead.

The launcher logic lives in `run-server.ps1`, not the .bat. Batch mangles
nested quotes and pipes inside `for /f` - `^|` reached PowerShell literally
and IP detection died silently, printing no address for friends to use.

- host plays on `/connect localhost`
- friends use `/connect <the LAN IP the .bat prints>` (a 192.168.x.x address)

Friends need any Sauerbraten 2020 / SwiftGibs client - protocol 260, and fdm6
is a stock map, so no downloads are needed.

## Test it

    tools/local-insta-server/test-server.sh

`spawnprobe.cc` is a headless protocol-260 client (no SDL/audio - safe under
WSLg). On test port 28985 it asserts the boot map/mode, then proves instant
respawn on both death paths (suicide, and a real rifle kill between two probe
clients) by watching for an UNSOLICITED spawnstate - the probe never sends
N_TRYSPAWN. An `autospawn 0` control run proves the probe can fail.
