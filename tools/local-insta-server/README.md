# Local insta server

A local instagib FFA server that boots straight into **fdm6** with **instant
respawns**: the server force-respawns dead players itself about 300ms after
death (the engine's hit-event flush window) - no clicking, no waiting.

Stock protocol 260, so any SwiftGibs or Sauerbraten 2020 client can join.
Follows the mapbattle-testserver pattern: a scratch build tree under /tmp gets
the standard SwiftGibs patches plus `local-insta-server.patch`, which adds six
server cvars (none shipped in any bundle):

- `defaultmap` / `defaultmode` - map+mode loaded at boot and re-loaded whenever
  the server empties (fresh match every visit)
- `autospawn` - 1 = server respawns dead players itself (players who just
  joined or just loaded a map still self-spawn the vanilla way)
- `autospawndelay` - extra ms of death-cam on top of the 300ms flush window,
  if truly-instant ever feels too abrupt
- `instareload` / `instareloadgun` - a kill re-arms the killer's rifle; see
  "Insta reload" below

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

## Insta reload (a kill re-arms the rifle)

Toggle in game, from any client, no client changes needed:

    #instareload            (chat; toggles)      #instareload on / off
    /servcmd instareload    (same, as a / command - "/instareload" itself never
                             leaves a stock client: "/" runs client-side commands)

The server answers with a message everyone sees. Anyone may toggle while no
master or admin is on; once one is, only they may (note any player may claim
master with `/setmaster 1` while nobody holds it; the adminpass overrides).
Default is off; put `instareload 1` in server-init.cfg to boot with it on.
Only rifle kills count, so a voted non-insta mode keeps its other guns' rates.

What it does: the moment a rifle kill registers, the server drops the killer's
gun wait to the re-arm gun's delay (the most a stock client can use, so a
cheating client gains nothing) and sends the killer's client a two-message
packet that re-arms its own rifle gate. Why that is needed, and
why "instant" is really ~250ms: a stock 2020 client gates its own rifle purely
locally (`fpsgame/weapon.cpp shoot()`: no shot until
`lastmillis - lastaction >= gunwait`, 1500ms for the rifle), and the only
server message that touches those two fields on your own player is
`N_SHOTFX`, which the client applies to any cn including its own. So the
server tells the client it just fired `instareloadgun`, which sets the wait to
THAT gun's delay, then an `N_GUNSELECT` wrapped in `N_CLIENT` with the
killer's own cn puts the rifle back in the same packet, so no frame ever
shows the other gun. Nothing else the server can send resets the gate without
side effects (the respawn messages also zero it, but they teleport you or
clear your velocity and held keys).

- `instareloadgun 0` (fist, default): ready 250ms after the re-arm reaches the
  client (so ~250ms plus half a round trip after the kill registers).
  Side effects: a ~300ms chainsaw rev (the fist's attack sound; the stock
  `chainsawhudgun 1` default) and the weapon-load click. A player who sets
  `/chainsawhudgun 0` hears a punch whoosh instead.
- `instareloadgun 2` (chaingun): ready after 100ms, but with a chaingun bang,
  hud muzzle flash and a tracer. Louder and flashier; try it, see which reads
  better in a duel.

Measured with a real, unmodified 2020 client (test-client.sh below): the
next shot landed ~540ms after the kill, the script's own trigger timing; the
gate itself opened at ~270ms.

SwiftGibs clients: the reload countdown, ready flash and metronome all key on
`lastattackgun == GUN_RIFLE`, so after the fist re-arm they simply vanish (no
ready cue) and the reload-charge sound still plays its full 1.5s; replay
clips keep the fist rev. A small client patch could turn the self N_SHOTFX
into a proper "ready" cue if the mode sticks - deliberately not done here.

## Test it

    tools/local-insta-server/test-server.sh

Run the two scripts one at a time: they share the /tmp build tree and port.
`spawnprobe.cc` is a headless protocol-260 client (no SDL/audio - safe under
WSLg). On test port 28985 it asserts the boot map/mode, then proves instant
respawn on both death paths (suicide, and a real rifle kill between two probe
clients) by watching for an UNSOLICITED spawnstate - the probe never sends
N_TRYSPAWN. An `autospawn 0` control run proves the probe can fail. The insta
reload scenarios then prove the server half from the wire: off by default (a
shot 300ms after a kill is rejected, no re-arm traffic), `/servcmd instareload
on` re-arms the killer (self N_SHOTFX + wrapped N_GUNSELECT) and the 300ms
follow-up shot kills, the master-only rule, and `instareloadgun 2`.

    tools/local-insta-server/test-client.sh

proves the half a player feels, against a REAL stock client: the vanilla 2020
tree at `~/repos/sauerbraten/src` plus `harness-client.patch`, which only adds
script hooks (fire, spawn, aim, reload-state dump) so a `-x` script can drive
it headless (SDL offscreen video on llvmpipe, dummy audio). The idle probe
parks a victim 10 units in front of the client; the client kills it, dumps
its gate, then shoots the bystander that takes the victim's spot. Mode on: the
dump shows the fist re-arm and the bystander dies ~500ms after the victim.
Mode off (control): the stock 1500ms gate holds and no second shot happens.
Each mode takes ~40s, mostly waiting for the software-rendered map load.
