// spawnprobe - protocol-level test client for the local insta server.
// Joins as a real Sauerbraten protocol-260 client (no video/audio/SDL) and
// verifies the server's behaviour from the wire:
//
//   spawnprobe <port> suicide   join, assert map/mode, suicide, expect an
//                               UNSOLICITED N_SPAWNSTATE (we never send
//                               N_TRYSPAWN) -> proves autospawn
//   spawnprobe <port> kill      two clients; killer lands a real rifle hit on
//                               victim, victim expects N_DIED then an
//                               unsolicited N_SPAWNSTATE
//   spawnprobe <port> nospawn   control: suicide, expect NO spawnstate within
//                               1.5s (run against a server with autospawn 0 -
//                               proves the probe can fail)
//   spawnprobe <port> instareload
//                               three clients; killer turns the mode on with
//                               "/servcmd instareload on", kills the victim,
//                               expects the server's re-arm pair back (an
//                               N_SHOTFX for ITSELF with the fx gun, then an
//                               N_CLIENT-wrapped N_GUNSELECT restoring its
//                               rifle), and 300ms later kills the bystander -
//                               a shot the stock 1500ms rifle wait would reject
//   spawnprobe <port> instareload-off
//                               control, mode off: killer gets no self
//                               N_SHOTFX and the 300ms follow-up shot is
//                               rejected (bystander survives)
//   spawnprobe <port> instareload-master
//                               killer claims master (server needs
//                               publicserver 2), turns the mode off by chat
//                               "#instareload off"; the bystander's
//                               "#instareload on" is refused while a master is
//                               on; follow-up shot still rejected
//
//   spawnprobe <port> idle      stand-in victim (cn 0) + bystander (cn 1) for
//                               test-client.sh: parked in front of a REAL
//                               client, which kills them in turn; prints each
//                               first death as +ms and the gap between them
//                               (SPAWNPROBE_IDLE_MS, default 60s)
//
// SPAWNPROBE_FXGUN = gun index expected in the re-arm N_SHOTFX (default 0 =
// fist, i.e. the server's instareloadgun default).
//
// Set SPAWNPROBE_HOST to test a server that is not on 127.0.0.1 (e.g. the
// native Windows server over the LAN: SPAWNPROBE_HOST=192.168.1.42).
//
// SPAWNPROBE_PASSWORD joins a serverpass-protected server. Sauerbraten never
// sends the password itself: the client sends a Tiger hash of
// "<clientnum> <sessionid> <password>", which the server recomputes. That
// needs the engine's own hashstring(), so password support is compiled in
// only with -DUSE_CUBE_CRYPTO, linking the server tree's crypto object:
//   g++ -DUSE_CUBE_CRYPTO spawnprobe.cc shared/crypto-standalone.o \
//       shared/tools-standalone.o shared/stream-standalone.o -Ienet/include \
//       -Lenet -lenet -lz -o spawnprobe
#ifdef USE_CUBE_CRYPTO
extern bool hashstring(const char *str, char *result, int maxlen);
#endif
//
// Exit 0 = PASS, 1 = FAIL, 2 = protocol desync/setup error.
// Build: g++ -O2 spawnprobe.cc -o spawnprobe -I<tree>/enet/include -L<tree>/enet -lenet

#include <enet/enet.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <cmath>

static void die(const char *why);

// --- netmsg enum, copied verbatim from fpsgame/game.h (protocol 260) ---
enum
{
    N_CONNECT = 0, N_SERVINFO, N_WELCOME, N_INITCLIENT, N_POS, N_TEXT, N_SOUND, N_CDIS,
    N_SHOOT, N_EXPLODE, N_SUICIDE,
    N_DIED, N_DAMAGE, N_HITPUSH, N_SHOTFX, N_EXPLODEFX,
    N_TRYSPAWN, N_SPAWNSTATE, N_SPAWN, N_FORCEDEATH,
    N_GUNSELECT, N_TAUNT,
    N_MAPCHANGE, N_MAPVOTE, N_TEAMINFO, N_ITEMSPAWN, N_ITEMPICKUP, N_ITEMACC, N_TELEPORT, N_JUMPPAD,
    N_PING, N_PONG, N_CLIENTPING,
    N_TIMEUP, N_FORCEINTERMISSION,
    N_SERVMSG, N_ITEMLIST, N_RESUME,
    N_EDITMODE, N_EDITENT, N_EDITF, N_EDITT, N_EDITM, N_FLIP, N_COPY, N_PASTE, N_ROTATE, N_REPLACE, N_DELCUBE, N_REMIP, N_EDITVSLOT, N_UNDO, N_REDO, N_NEWMAP, N_GETMAP, N_SENDMAP, N_CLIPBOARD, N_EDITVAR,
    N_MASTERMODE, N_KICK, N_CLEARBANS, N_CURRENTMASTER, N_SPECTATOR, N_SETMASTER, N_SETTEAM,
    N_BASES, N_BASEINFO, N_BASESCORE, N_REPAMMO, N_BASEREGEN, N_ANNOUNCE,
    N_LISTDEMOS, N_SENDDEMOLIST, N_GETDEMO, N_SENDDEMO,
    N_DEMOPLAYBACK, N_RECORDDEMO, N_STOPDEMO, N_CLEARDEMOS,
    N_TAKEFLAG, N_RETURNFLAG, N_RESETFLAG, N_INVISFLAG, N_TRYDROPFLAG, N_DROPFLAG, N_SCOREFLAG, N_INITFLAGS,
    N_SAYTEAM,
    N_CLIENT,
    N_AUTHTRY, N_AUTHKICK, N_AUTHCHAL, N_AUTHANS, N_REQAUTH,
    N_PAUSEGAME, N_GAMESPEED,
    N_ADDBOT, N_DELBOT, N_INITAI, N_FROMAI, N_BOTLIMIT, N_BOTBALANCE,
    N_MAPCRC, N_CHECKMAPS,
    N_SWITCHNAME, N_SWITCHMODEL, N_SWITCHTEAM,
    N_INITTOKENS, N_TAKETOKEN, N_EXPIRETOKENS, N_DROPTOKENS, N_DEPOSITTOKENS, N_STEALTOKENS,
    N_SERVCMD,
    N_DEMOPACKET,
    NUMMSG
};

static const int GUN_FIST = 0, GUN_RIFLE = 4;
static const float DMF = 16.0f, DNF = 100.0f;

// --- cube int/string wire encoding, ported from shared/tools.cpp ---
struct buf
{
    const unsigned char *data; int len, pos; bool over;
    buf(const unsigned char *d, int l) : data(d), len(l), pos(0), over(false) {}
    int get() { if(pos >= len) { over = true; return 0; } return data[pos++]; }
    void skip(int n) { pos += n; if(pos > len) { pos = len; over = true; } }
    bool done() const { return pos >= len; }
};
static int getint(buf &p)
{
    int c = (char)p.get();
    if(c == -128) { int n = p.get(); n |= char(p.get()) << 8; return n; }
    else if(c == -127) { int n = p.get(); n |= p.get() << 8; n |= p.get() << 16; return n | (p.get() << 24); }
    else return c;
}
static int getuint(buf &p)
{
    int n = p.get();
    if(n & 0x80)
    {
        n += (p.get() << 7) - 0x80;
        if(n & (1<<14)) n += (p.get() << 14) - (1<<14);
        if(n & (1<<21)) n += (p.get() << 21) - (1<<21);
        if(n & (1<<28)) n |= ~0U << 28;
    }
    return n;
}
static std::string getstr(buf &p)
{
    std::string s;
    for(;;) { int c = getint(p); if(!c || p.over) break; s += (char)c; }
    return s;
}
static void putint(std::vector<unsigned char> &p, int n)
{
    if(n < 128 && n > -127) p.push_back(n);
    else if(n < 0x8000 && n >= -0x8000) { p.push_back(0x80); p.push_back(n); p.push_back(n >> 8); }
    else { p.push_back(0x81); p.push_back(n); p.push_back(n >> 8); p.push_back(n >> 16); p.push_back(n >> 24); }
}
static void putuint(std::vector<unsigned char> &p, int n) // small values only (cn, flags) - one byte on the wire
{
    if(n < 0 || n >= 0x80) die("putuint: value out of the one-byte range this probe supports");
    p.push_back(n);
}
static void putstr(std::vector<unsigned char> &p, const char *s)
{
    while(*s) putint(p, *s++);
    putint(p, 0);
}

// --- one probe connection ---
struct Conn
{
    const char *name;
    ENetHost *host = NULL;
    ENetPeer *peer = NULL;
    int cn = -1, sessionid = 0, lifeseq = -1, gunsel = 1, mode = -1;
    std::string map;
    bool welcomed = false, alive = false;
    int spawnstates = 0, tryspawnsSent = 0, diedcount = 0;
    int selfshotfx = 0, selfshotfxgun = -1, wrappedgunsel = -1; // insta reload re-arm pair, see header
    std::string lastservmsg;
    // last N_POS seen from a client that is not one of ours (the real client in test-client.sh)
    bool anchorseen = false; int anchorcn = -1; float anchorx = 0, anchory = 0, anchorz = 0, anchoryaw = 0;

    void sendmsg(const std::vector<unsigned char> &m)
    {
        ENetPacket *pkt = enet_packet_create(m.data(), m.size(), ENET_PACKET_FLAG_RELIABLE);
        enet_peer_send(peer, 1, pkt);
    }
};

static void die(const char *why)
{
    fprintf(stderr, "PROTOCOL ERROR: %s\n", why);
    exit(2);
}

static void skipstate(buf &p) { for(int i = 0; i < 12; i++) getint(p); } // lifeseq,health,maxhealth,armour,armourtype,gunselect,ammo x6

static void handlemsg(Conn &c, buf &p)
{
    int type = getint(p);
    switch(type)
    {
        case N_SERVINFO:
        {
            c.cn = getint(p);
            int prot = getint(p); c.sessionid = getint(p); int haspwd = getint(p);
            getstr(p); getstr(p); // serverdesc, serverauth
            if(prot != 260) die("protocol mismatch");
            const char *pwd = getenv("SPAWNPROBE_PASSWORD");
            if(!pwd) pwd = "";
            char sendpwd[260] = "";
            if(haspwd)
            {
                if(!pwd[0]) die("server is passworded - set SPAWNPROBE_PASSWORD");
#ifdef USE_CUBE_CRYPTO
                char buf[520];
                snprintf(buf, sizeof(buf), "%d %d %s", c.cn, c.sessionid, pwd);
                if(!hashstring(buf, sendpwd, sizeof(sendpwd))) die("hashstring failed");
#else
                die("password support needs -DUSE_CUBE_CRYPTO (see header comment)");
#endif
            }
            std::vector<unsigned char> m;
            putint(m, N_CONNECT); putstr(m, c.name); putint(m, 0); // playermodel
            putstr(m, sendpwd); putstr(m, ""); putstr(m, "");      // pwd hash, authdesc, authname
            c.sendmsg(m);
            break;
        }
        case N_WELCOME: c.welcomed = true; break;
        case N_MAPCHANGE: c.map = getstr(p); c.mode = getint(p); getint(p); break;
        case N_TIMEUP: getint(p); break;
        case N_SETTEAM: getint(p); getstr(p); getint(p); break;
        case N_SPAWNSTATE:
        {
            int scn = getint(p);
            int ls = getint(p);
            for(int i = 0; i < 4; i++) getint(p); // health,maxhealth,armour,armourtype
            int gun = getint(p);
            for(int i = 0; i < 6; i++) getint(p); // ammo
            if(scn == c.cn)
            {
                c.lifeseq = ls; c.gunsel = gun; c.spawnstates++;
                std::vector<unsigned char> m;   // ack, as fpsgame/client.cpp does
                putint(m, N_SPAWN); putint(m, ls); putint(m, gun);
                c.sendmsg(m);
                c.alive = true;
            }
            break;
        }
        case N_RESUME:
            for(;;)
            {
                int scn = getint(p);
                if(scn < 0 || p.over) break;
                for(int i = 0; i < 5; i++) getint(p); // state,frags,flags,deaths,quadmillis
                skipstate(p);
            }
            break;
        case N_INITCLIENT: getint(p); getstr(p); getstr(p); getint(p); break;
        case N_CDIS: getint(p); break;
        case N_SERVMSG: c.lastservmsg = getstr(p); break;
        case N_DIED:
        {
            int victim = getint(p);
            for(int i = 0; i < 3; i++) getint(p); // actor, frags, teamfrags
            if(victim == c.cn) { c.alive = false; c.diedcount++; }
            break;
        }
        case N_DAMAGE: for(int i = 0; i < 5; i++) getint(p); break;
        case N_HITPUSH: for(int i = 0; i < 6; i++) getint(p); break;
        case N_SHOTFX:
        {
            int scn = getint(p), gun = getint(p);
            for(int i = 0; i < 7; i++) getint(p); // id, from xyz, to xyz
            // a stock server never echoes a client's own shot back to it ("rii9x" excludes the
            // shooter), so an N_SHOTFX about OURSELVES is the insta reload re-arm and nothing else
            if(scn == c.cn) { c.selfshotfx++; c.selfshotfxgun = gun; }
            break;
        }
        case N_EXPLODEFX: for(int i = 0; i < 3; i++) getint(p); break;
        case N_FORCEDEATH: getint(p); break;
        case N_CURRENTMASTER:
            getint(p); // mastermode
            for(;;) { int scn = getint(p); if(scn < 0 || p.over) break; getint(p); }
            break;
        case N_ITEMLIST:
            for(;;) { int i = getint(p); if(i < 0 || p.over) break; getint(p); }
            break;
        case N_TEAMINFO:
            for(;;) { std::string t = getstr(p); if(t.empty() || p.over) break; getint(p); }
            break;
        case N_ANNOUNCE: case N_ITEMSPAWN: case N_PONG: case N_CLIENTPING: getint(p); break;
        case N_ITEMACC: case N_SPECTATOR: case N_PAUSEGAME: case N_GAMESPEED: getint(p); getint(p); break;
        case N_INITAI: for(int i = 0; i < 5; i++) getint(p); getstr(p); getstr(p); break;
        case N_CLIENT:
        {
            int scn = getint(p); int len = getuint(p);
            if(len > p.len - p.pos) len = p.len - p.pos; // never read past the packet on a bad length
            if(scn == c.cn) // only insta reload wraps a message in OUR cn: expect N_GUNSELECT <gun>
            {
                buf q(p.data + p.pos, len);
                if(getint(q) == N_GUNSELECT) c.wrappedgunsel = getint(q);
            }
            p.skip(len); // relayed traffic from others: skip wholesale
            break;
        }
        default:
        {
            char msg[64];
            snprintf(msg, sizeof(msg), "unhandled message type %d at offset %d", type, p.pos);
            die(msg);
        }
    }
    if(p.over) die("overread while parsing");
}

// N_POS of another client, relayed by the server on channel 0 (encoding: fpsgame/client.cpp
// sendposition/parsepositions). Only the feet position and yaw are kept, and only for a client
// that is not one of ours.
static void handlepos(Conn &c, buf &p, Conn *conns[], int nconns)
{
    int type = getint(p);
    if(type != N_POS) { p.skip(p.len); return; } // anything else on channel 0: ignore the rest of the packet
    int cn = getuint(p); p.get(); int flags = getuint(p);
    float o[3];
    for(int k = 0; k < 3; k++)
    {
        int n = p.get(); n |= p.get() << 8;
        if(flags & (1 << k)) { n |= p.get() << 16; if(n & 0x800000) n |= ~0U << 24; }
        o[k] = n / DMF;
    }
    int dir = p.get(); dir |= p.get() << 8;
    p.get();                                   // roll
    p.get(); if(flags & (1 << 3)) p.get();     // velocity magnitude
    p.get(); p.get();                          // velocity direction
    if(flags & (1 << 4)) { p.get(); if(flags & (1 << 5)) p.get(); if(flags & (1 << 6)) { p.get(); p.get(); } }
    for(int i = 0; i < nconns; i++) if(conns[i]->cn == cn) return; // one of ours
    c.anchorseen = true; c.anchorcn = cn; c.anchorx = o[0]; c.anchory = o[1]; c.anchorz = o[2]; c.anchoryaw = dir % 360;
}

// Stand still at feet position (x,y,z) facing yaw: the real client then sees us alive there
// (a player with no position updates for 1s goes CS_LAGGED and cannot be hit).
static void sendpos(Conn &c, float x, float y, float z, int yaw)
{
    std::vector<unsigned char> m;
    putint(m, N_POS);
    putuint(m, c.cn);
    m.push_back(4 /*PHYS_FLOOR*/ | ((c.lifeseq & 1) << 3));
    putuint(m, 0);                             // flags: all coords fit 16 bits, no velocity, not falling
    int o[3] = { int(x * DMF), int(y * DMF), int(z * DMF) };
    for(int k = 0; k < 3; k++) { if(o[k] < 0 || o[k] > 0xFFFF) die("sendpos: coordinate out of range"); m.push_back(o[k] & 0xFF); m.push_back((o[k] >> 8) & 0xFF); }
    int d = ((yaw % 360) + 360) % 360 + 90 * 360;  // yaw + (pitch 0 + 90) * 360
    m.push_back(d & 0xFF); m.push_back((d >> 8) & 0xFF);
    m.push_back(90);                           // roll 0
    m.push_back(0);                            // velocity 0
    m.push_back(0); m.push_back(0);            // velocity direction
    ENetPacket *pkt = enet_packet_create(m.data(), m.size(), 0);
    enet_peer_send(c.peer, 0, pkt);
}

static void pump(Conn *conns[], int nconns, int ms)
{
    ENetEvent ev;
    int waited = 0;
    while(waited < ms)
    {
        for(int i = 0; i < nconns; i++)
        {
            while(enet_host_service(conns[i]->host, &ev, 5) > 0)
            {
                if(ev.type == ENET_EVENT_TYPE_RECEIVE)
                {
                    if(ev.channelID == 1)
                    {
                        buf p(ev.packet->data, (int)ev.packet->dataLength);
                        while(!p.done()) handlemsg(*conns[i], p);
                    }
                    else if(ev.channelID == 0)
                    {
                        buf p(ev.packet->data, (int)ev.packet->dataLength);
                        while(!p.done() && !p.over) handlepos(*conns[i], p, conns, nconns);
                    }
                    enet_packet_destroy(ev.packet);
                }
                else if(ev.type == ENET_EVENT_TYPE_DISCONNECT) die("server disconnected us");
            }
        }
        waited += 5 * nconns;
    }
}

static std::vector<Conn *> allconns;

// Disconnect cleanly on the way out. A probe that just exits leaves its peers on the server
// until the enet timeout (~30s), and three scenarios in a row then hit "server FULL".
static void leaveall()
{
    for(Conn *c : allconns) if(c->peer) enet_peer_disconnect(c->peer, 0);
    for(Conn *c : allconns)
    {
        ENetEvent ev;
        for(int waited = 0; waited < 500 && c->peer; waited += 10)
            while(enet_host_service(c->host, &ev, 10) > 0)
            {
                if(ev.type == ENET_EVENT_TYPE_RECEIVE) enet_packet_destroy(ev.packet);
                else if(ev.type == ENET_EVENT_TYPE_DISCONNECT) { c->peer = NULL; break; }
            }
        if(c->peer) enet_peer_reset(c->peer);
    }
}

static Conn *join(const char *name, int port)
{
    Conn *c = new Conn;
    allconns.push_back(c);
    c->name = name;
    c->host = enet_host_create(NULL, 1, 3, 0, 0);
    if(!c->host) die("enet_host_create failed");
    ENetAddress addr;
    const char *host = getenv("SPAWNPROBE_HOST");
    if(!host || !host[0]) host = "127.0.0.1";
    if(enet_address_set_host(&addr, host) < 0) die("could not resolve SPAWNPROBE_HOST");
    addr.port = port;
    c->peer = enet_host_connect(c->host, &addr, 3, 0);
    ENetEvent ev;
    if(enet_host_service(c->host, &ev, 3000) <= 0 || ev.type != ENET_EVENT_TYPE_CONNECT)
        die("could not connect to server (is it running?)");
    Conn *cs[1] = { c };
    for(int i = 0; i < 200 && !c->alive; i++) pump(cs, 1, 10);
    if(!c->alive) die("never received our spawnstate from the welcome");
    return c;
}

static bool waitrespawn(Conn *conns[], int nconns, Conn &who, int timeoutms, int *latency)
{
    int before = who.spawnstates;
    for(int waited = 0; waited < timeoutms; waited += 10)
    {
        pump(conns, nconns, 10);
        if(who.spawnstates > before) { if(latency) *latency = waited; return true; }
    }
    return false;
}

static void shootat(Conn &shooter, Conn &target, int millis) // one rifle ray straight into target
{
    std::vector<unsigned char> m;
    putint(m, N_SHOOT);
    putint(m, millis);              // shot id doubles as client millis; server resyncs on the first event
    putint(m, GUN_RIFLE);
    putint(m, int(512*DMF)); putint(m, int(512*DMF)); putint(m, int(512*DMF)); // from
    putint(m, int(513*DMF)); putint(m, int(512*DMF)); putint(m, int(512*DMF)); // to
    putint(m, 1);                   // one hit:
    putint(m, target.cn); putint(m, target.lifeseq);
    putint(m, int(1*DMF));          // dist
    putint(m, 1);                   // rays
    putint(m, int(1*DNF)); putint(m, 0); putint(m, 0); // dir
    shooter.sendmsg(m);
}

static void say(Conn &c, const char *text) { std::vector<unsigned char> m; putint(m, N_TEXT); putstr(m, text); c.sendmsg(m); }
static void servcmd(Conn &c, const char *text) { std::vector<unsigned char> m; putint(m, N_SERVCMD); putstr(m, text); c.sendmsg(m); }
static void claimmaster(Conn &c) { std::vector<unsigned char> m; putint(m, N_SETMASTER); putint(m, c.cn); putint(m, 1); putstr(m, ""); c.sendmsg(m); }

static bool waitdied(Conn *conns[], int nconns, Conn &who, int timeoutms)
{
    int before = who.diedcount;
    for(int waited = 0; waited < timeoutms; waited += 10)
    {
        pump(conns, nconns, 10);
        if(who.diedcount > before) return true;
    }
    return false;
}

static bool waitservmsg(Conn *conns[], int nconns, Conn &who, const char *needle, int timeoutms)
{
    who.lastservmsg.clear();
    for(int waited = 0; waited < timeoutms; waited += 10)
    {
        pump(conns, nconns, 10);
        if(who.lastservmsg.find(needle) != std::string::npos) return true;
    }
    return false;
}

// insta reload scenarios share one shape: killer A frags victim B, then 300ms later (by the
// client clock the server is told) shoots bystander C. Stock rifle wait is 1500ms, so the
// follow-up lands only if the server re-armed A on the kill (its wait becomes the fx gun's:
// 250ms fist, 100ms chaingun - the server keeps that much of a rate limit on purpose).
static int instareloadround(Conn *cs[], Conn &a, Conn &b, Conn &c, bool expecton, int fxgun)
{
    a.selfshotfx = 0; a.selfshotfxgun = -1; a.wrappedgunsel = -1;
    shootat(a, b, 100);
    if(!waitdied(cs, 3, b, 1000)) { printf("FAIL: rifle hit did not kill the victim\n"); return 1; }
    pump(cs, 3, 50); // let the re-arm pair (sent right after N_DIED) arrive
    if(expecton)
    {
        if(a.selfshotfx != 1) { printf("FAIL: expected exactly one self N_SHOTFX re-arm, got %d\n", a.selfshotfx); return 1; }
        if(a.selfshotfxgun != fxgun) { printf("FAIL: re-arm N_SHOTFX gun %d, expected %d\n", a.selfshotfxgun, fxgun); return 1; }
        if(a.wrappedgunsel != GUN_RIFLE) { printf("FAIL: expected a wrapped N_GUNSELECT rifle (4), got %d\n", a.wrappedgunsel); return 1; }
    }
    else if(a.selfshotfx || a.wrappedgunsel >= 0)
    { printf("FAIL: mode off but got re-arm traffic (selfshotfx=%d wrappedgunsel=%d)\n", a.selfshotfx, a.wrappedgunsel); return 1; }
    shootat(a, c, 400); // 300ms after the kill shot on the client clock
    bool cdied = waitdied(cs, 3, c, 1000);
    if(expecton && !cdied) { printf("FAIL: follow-up shot 300ms after the kill was rejected (server wait not reset)\n"); return 1; }
    if(!expecton && cdied) { printf("FAIL: follow-up shot 300ms after the kill was ACCEPTED with the mode off\n"); return 1; }
    return 0;
}

static int run(int argc, char **argv);
int main(int argc, char **argv) { int rc = run(argc, argv); leaveall(); return rc; }

static int run(int argc, char **argv)
{
    if(argc != 3) { fprintf(stderr, "usage: spawnprobe <port> <suicide|kill|nospawn|instareload|instareload-off|instareload-master|idle>\n"); return 2; }
    int port = atoi(argv[1]);
    const char *scen = argv[2];
    if(enet_initialize() < 0) die("enet_initialize failed");

    if(!strcmp(scen, "suicide") || !strcmp(scen, "nospawn"))
    {
        Conn *c = join("probe", port);
        printf("joined as cn %d: map \"%s\" mode %d\n", c->cn, c->map.c_str(), c->mode);
        if(c->map != "fdm6" || c->mode != 3)
        { printf("FAIL: expected map fdm6 mode 3 (instagib)\n"); return 1; }
        Conn *cs[1] = { c };
        pump(cs, 1, 300); // settle
        std::vector<unsigned char> m;
        putint(m, N_SUICIDE);
        c->sendmsg(m);
        int latency = -1;
        bool respawned = waitrespawn(cs, 1, *c, 2000, &latency);
        if(!c->diedcount) { printf("FAIL: suicide never registered (no N_DIED)\n"); return 1; }
        if(!strcmp(scen, "suicide"))
        {
            if(!respawned) { printf("FAIL: no autospawn within 2000ms of suicide\n"); return 1; }
            printf("PASS: died and auto-respawned in ~%dms with zero N_TRYSPAWN sent (tryspawns=%d)\n",
                   latency, c->tryspawnsSent);
        }
        else // nospawn control
        {
            if(respawned) { printf("FAIL: got a spawnstate despite autospawn 0\n"); return 1; }
            printf("PASS: stayed dead (control) - no spawnstate within 2000ms\n");
        }
        return 0;
    }
    if(!strcmp(scen, "kill"))
    {
        Conn *a = join("killer", port);
        Conn *b = join("victim", port);
        Conn *cs[2] = { a, b };
        pump(cs, 2, 400); // let RESUME/INITCLIENT settle
        int oldls = b->lifeseq;
        shootat(*a, *b, 100);
        int latency = -1;
        bool respawned = waitrespawn(cs, 2, *b, 2000, &latency);
        if(!b->diedcount) { printf("FAIL: rifle hit did not kill the victim\n"); return 1; }
        if(!respawned) { printf("FAIL: victim not auto-respawned within 2000ms of death\n"); return 1; }
        if(((oldls + 1) & 0x7F) != b->lifeseq)
        { printf("FAIL: lifesequence %d -> %d (expected +1)\n", oldls, b->lifeseq); return 1; }
        printf("PASS: victim killed by rifle and auto-respawned in ~%dms (lifeseq %d -> %d)\n",
               latency, oldls, b->lifeseq);
        return 0;
    }
    if(!strncmp(scen, "instareload", 11))
    {
        const char *fx = getenv("SPAWNPROBE_FXGUN");
        int fxgun = fx && fx[0] ? atoi(fx) : GUN_FIST;
        Conn *a = join("killer", port);
        Conn *b = join("victim", port);
        Conn *c = join("bystander", port);
        Conn *cs[3] = { a, b, c };
        pump(cs, 3, 400); // let RESUME/INITCLIENT settle
        if(!strcmp(scen, "instareload"))
        {
            servcmd(*a, "instareload on");
            if(!waitservmsg(cs, 3, *a, "ON", 1000)) { printf("FAIL: '/servcmd instareload on' not acknowledged\n"); return 1; }
            if(instareloadround(cs, *a, *b, *c, true, fxgun)) return 1;
            printf("PASS: kill re-armed the killer (self N_SHOTFX gun %d + wrapped N_GUNSELECT rifle) and a shot 300ms later killed the bystander\n", fxgun);
            return 0;
        }
        if(!strcmp(scen, "instareload-off"))
        {
            if(instareloadround(cs, *a, *b, *c, false, fxgun)) return 1;
            printf("PASS: mode off (control) - no re-arm traffic and the 300ms follow-up shot was rejected\n");
            return 0;
        }
        if(!strcmp(scen, "instareload-master"))
        {
            claimmaster(*a);
            pump(cs, 3, 300);
            say(*a, "#instareload off");
            if(!waitservmsg(cs, 3, *a, "OFF", 1000)) { printf("FAIL: master's '#instareload off' not acknowledged\n"); return 1; }
            say(*c, "#instareload on");
            if(!waitservmsg(cs, 3, *c, "master", 1000)) { printf("FAIL: non-master toggle was not refused while a master is on\n"); return 1; }
            if(instareloadround(cs, *a, *b, *c, false, fxgun)) return 1;
            printf("PASS: master toggled off by chat, bystander's toggle refused, follow-up shot rejected\n");
            return 0;
        }
    }
    if(!strcmp(scen, "idle"))
    {
        Conn *b = join("victim", port);
        Conn *c = join("bystander", port);
        Conn *cs[2] = { b, c };
        printf("idle: victim cn %d, bystander cn %d\n", b->cn, c->cn); fflush(stdout);
        const char *lim = getenv("SPAWNPROBE_IDLE_MS");
        int limit = lim && lim[0] ? atoi(lim) : 60000;
        int start = (int)enet_time_get(), bdied = -1, cdied = -1, lastpos = 0;
        bool anchored = false;
        while((int)enet_time_get() - start < limit)
        {
            pump(cs, 2, 10);
            int now = (int)enet_time_get() - start;
            // Once the real client is seen, park the victim 10 units ahead along its yaw, facing it.
            // The bystander waits behind the client and takes over the victim's spot (proven open by
            // the hit) the moment the victim dies; the dead victim stops updating so its autospawned
            // self does not stroll back into the line of fire.
            Conn *anchor = b->anchorseen ? b : (c->anchorseen ? c : NULL);
            if(anchor && now - lastpos >= 30)
            {
                lastpos = now;
                float yaw = anchor->anchoryaw, rad = yaw * 3.14159265f / 180;
                float fx = -sinf(rad), fy = cosf(rad);
                float ax = anchor->anchorx, ay = anchor->anchory, az = anchor->anchorz;
                if(!anchored) { anchored = true; printf("anchored on cn %d at %.1f %.1f %.1f yaw %d\n", anchor->anchorcn, ax, ay, az, (int)yaw); fflush(stdout); }
                if(!b->diedcount) sendpos(*b, ax + fx * 10, ay + fy * 10, az, int(yaw) + 180);
                else if(!c->diedcount) sendpos(*c, ax + fx * 10, ay + fy * 10, az, int(yaw) + 180);
                if(!b->diedcount) sendpos(*c, ax - fx * 10, ay - fy * 10, az, int(yaw));
            }
            if(bdied < 0 && b->diedcount) { bdied = now; printf("DIED victim +%dms\n", bdied); fflush(stdout); }
            if(cdied < 0 && c->diedcount) { cdied = now; printf("DIED bystander +%dms\n", cdied); fflush(stdout); }
            if(bdied >= 0 && cdied >= 0) break;
        }
        if(bdied < 0) { printf("RESULT victim never died\n"); return 1; }
        if(cdied < 0) { printf("RESULT bystander never died (victim died at +%dms)\n", bdied); return 1; }
        printf("RESULT gap %dms (victim +%dms, bystander +%dms)\n", cdied - bdied, bdied, cdied);
        return 0;
    }
    fprintf(stderr, "unknown scenario %s\n", scen);
    return 2;
}
