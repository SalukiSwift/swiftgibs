// harness-main.cpp: standalone driver for mapstream.cpp's downloader
// contract (mapstreambegin/state/progress/statustext/cancel), used to prove
// the five fault-mode behaviors in an environment where the real engine
// client cannot currently boot headless (see task-5-report.md for why).
// Links against the SAME mapstream.cpp/sgsha256.cpp/sghttp.cpp compiled for
// the real client - see harness-stubs.cpp for the minimal engine-symbol
// stubs used in place of the full renderer/console/scripting engine.
//
// usage: harness <mapname> [cancel-after-ms]
// Requires CWD to contain data/mapmanifest.cfg and packages/base/ (the
// "no homedir set" resolution mode - see harness-stubs.cpp). The URL is
// read from the MAPSTREAM_TEST_URL environment variable and poked directly
// into the mapstreamurl global before starting (there is no scripting
// console in this harness to set an SVARP through).
//
// Prints one "HARNESS: <text>" line per observed statustext change (mirrors
// mapstreamwaitloop()'s diff-and-log loop in mapstream.cpp, built from the
// same public state/progress/statustext contract, since mapstreamwaitloop
// itself has internal linkage and can't be called from another
// translation unit), then a final "HARNESS: RESULT state=... elapsed_ms=..."
// line. If cancel-after-ms is given and the fetch is still MS_ACTIVE once
// that much time has passed, calls mapstreamcancel() once.
//
// usage: harness --hook <mapname> [cancel-after-ms]
// Task 6: mimics the changemap-seam hook's own orchestration sequence
// (fpsgame/client.cpp) line for line - presence check via
// mapstreamogzpath()/fileexists()/findfile(), manifest check, begin(), a
// while(MS_ACTIVE) loop, a simulated interceptkey(SDLK_ESCAPE) (there is no
// real keyboard/UI in this harness, so "ESC pressed" is simulated the same
// way the plain scenario above already simulates a cancel: a cancel-after-ms
// timer) that calls mapstreamcancel() and breaks exactly like the real hook,
// and the same final "map download failed: %s" outcome branch, gated on the
// same state != MS_DONE check. Exercises the hook's LOGIC (this environment
// cannot currently boot the real client headless - see task-6-report.md);
// the seam's actual wiring into fpsgame/client.cpp is proven by compile-proof
// only. See harness-stubs.cpp for the getmapfilenames()/path()/fileexists()
// stubs mapstreamogzpath() needs that this mode newly pulls in.
//
// usage: harness --all [cancel-after-ms]
// Task 7: drives the bulk "download all maps" sweep directly through its own
// public contract (mapstreamallbegin/allisactive/alldonecount/alltotalcount/
// allfailedcount/allcancel - see mapstream.h) - the same functions the
// mapstreamall/mapstreamallsync/mapstreamallcancel ICOMMANDs wrap for the
// menu. Polls once per 20ms tick (same cadence mapstreamwaitloop() and the
// --hook scenario above use) printing "HARNESS: done=D total=T failed=F"
// whenever any of the three counts change, then a final "HARNESS: RESULT
// done=... total=... failed=... active=... elapsed_ms=..." line. If
// cancel-after-ms is given and the sweep is still active once that much time
// has passed, calls mapstreamallcancel() once - mirrors the plain scenario's
// own cancel-after-ms timer above.

#include "cube.h"
#include "mapstream.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int runhookscenario(const char *name, int cancelafterms)
{
    // Mirrors the seam's own precondition chain exactly (fpsgame/client.cpp):
    //   !m_edit && name[0] && !fileexists(findfile(mapstreamogzpath(name), "r"), "r")
    //      && mapmanifestfind(name) && mapstreambegin(name)
    // m_edit itself is a client.cpp/game.h concept this standalone harness
    // has no notion of - not exercised here, left to compile-proof + code
    // reading (see task-6-report.md self-review).
    bool present = fileexists(findfile(mapstreamogzpath(name), "r"), "r");
    printf("HOOK: present=%s\n", present ? "yes" : "no");
    if(present) { printf("HOOK: skip (already present)\n"); fflush(stdout); return 0; }

    if(!mapmanifestfind(name))
    {
        printf("HOOK: skip (no manifest entry)\n");
        fflush(stdout);
        return 0;
    }

    if(!mapstreambegin(name))
    {
        printf("HOOK: begin-failed\n");
        fflush(stdout);
        return 1;
    }

    Uint32 startticks = SDL_GetTicks();
    string lasttext; lasttext[0] = '\0';
    bool cancelsent = false;
    while(mapstreamstate() == MS_ACTIVE)
    {
        const char *text = mapstreamstatustext();
        if(strcmp(text, lasttext))
        {
            copystring(lasttext, text);
            printf("HOOK: %s\n", text);
            fflush(stdout);
        }

        Uint32 elapsed = SDL_GetTicks() - startticks;
        if(cancelafterms > 0 && !cancelsent && (int)elapsed >= cancelafterms)
        {
            cancelsent = true;
            mapstreamcancel();
            printf("HOOK: interceptkey(ESC) -> cancel\n");
            fflush(stdout);
            break;   // exactly matches the seam's "{ mapstreamcancel(); break; }"
        }
        SDL_Delay(20);
    }

    // Same gate as the seam: only conoutf's (here: prints) on a non-MS_DONE
    // outcome, using the identical format string as fpsgame/client.cpp's
    // conoutf(CON_ERROR, "map download failed: %s", mapstreamstatustext()).
    if(mapstreamstate() != MS_DONE) printf("HOOK: map download failed: %s\n", mapstreamstatustext());
    printf("HOOK: RESULT state=%s\n",
           mapstreamstate() == MS_DONE ? "MS_DONE" : mapstreamstate() == MS_FAILED ? "MS_FAILED" : "MS_OTHER");
    fflush(stdout);
    return 0;
}

// Task 7: bulk-sweep scenario - see the usage comment above.
static int runallscenario(int cancelafterms)
{
    Uint32 startticks = SDL_GetTicks();
    if(!mapstreamallbegin())
    {
        printf("HARNESS: begin-failed\n");
        fflush(stdout);
        return 1;
    }

    int lastdone = -1, lasttotal = -1, lastfailed = -1;
    bool cancelsent = false;
    while(mapstreamallisactive())
    {
        int done = mapstreamalldonecount(), total = mapstreamalltotalcount(), failed = mapstreamallfailedcount();
        if(done != lastdone || total != lasttotal || failed != lastfailed)
        {
            lastdone = done; lasttotal = total; lastfailed = failed;
            printf("HARNESS: done=%d total=%d failed=%d\n", done, total, failed);
            fflush(stdout);
        }

        Uint32 elapsed = SDL_GetTicks() - startticks;
        if(cancelafterms > 0 && !cancelsent && (int)elapsed >= cancelafterms)
        {
            cancelsent = true;
            mapstreamallcancel();
            printf("HARNESS: cancel requested at %ums\n", elapsed);
            fflush(stdout);
        }

        SDL_Delay(20);
    }

    Uint32 totalelapsed = SDL_GetTicks() - startticks;
    printf("HARNESS: RESULT done=%d total=%d failed=%d active=%d elapsed_ms=%u\n",
           mapstreamalldonecount(), mapstreamalltotalcount(), mapstreamallfailedcount(),
           mapstreamallisactive() ? 1 : 0, (unsigned)totalelapsed);
    fflush(stdout);
    return 0;
}

int main(int argc, char **argv)
{
    if(argc < 2)
    {
        fprintf(stderr, "usage: %s <mapname> [cancel-after-ms]\n", argv[0]);
        fprintf(stderr, "       %s --hook <mapname> [cancel-after-ms]\n", argv[0]);
        fprintf(stderr, "       %s --all [cancel-after-ms]\n", argv[0]);
        return 2;
    }

    bool hookmode = !strcmp(argv[1], "--hook");
    bool allmode = !hookmode && !strcmp(argv[1], "--all");
    if(hookmode && argc < 3)
    {
        fprintf(stderr, "usage: %s --hook <mapname> [cancel-after-ms]\n", argv[0]);
        return 2;
    }

    const char *url = getenv("MAPSTREAM_TEST_URL");
    if(url && url[0]) mapstreamurl = newstring(url);

    loadmapmanifest();

    if(allmode)
    {
        int cancelafter = argc > 2 ? atoi(argv[2]) : 0;
        return runallscenario(cancelafter);
    }

    const char *name = hookmode ? argv[2] : argv[1];
    int cancelafter = hookmode ? (argc > 3 ? atoi(argv[3]) : 0) : (argc > 2 ? atoi(argv[2]) : 0);

    if(hookmode) return runhookscenario(name, cancelafter);

    if(!mapmanifestfind(name))
    {
        fprintf(stderr, "HARNESS: no manifest entry for %s (check data/mapmanifest.cfg in CWD)\n", name);
        return 2;
    }

    Uint32 startticks = SDL_GetTicks();
    if(!mapstreambegin(name))
    {
        printf("HARNESS: begin-failed\n");
        fflush(stdout);
        return 1;
    }

    string lasttext; lasttext[0] = '\0';
    bool cancelsent = false;
    for(;;)
    {
        int state = mapstreamstate();
        if(state != MS_ACTIVE) break;

        const char *text = mapstreamstatustext();
        if(strcmp(text, lasttext))
        {
            copystring(lasttext, text);
            printf("HARNESS: %s\n", text);
            fflush(stdout);
        }

        Uint32 elapsed = SDL_GetTicks() - startticks;
        if(cancelafter > 0 && !cancelsent && (int)elapsed >= cancelafter)
        {
            cancelsent = true;
            mapstreamcancel();
            printf("HARNESS: cancel requested at %ums\n", elapsed);
            fflush(stdout);
        }

        SDL_Delay(20);
    }

    Uint32 totalelapsed = SDL_GetTicks() - startticks;
    int state = mapstreamstate();
    // mapstreamsettext() runs before the state atomic flips (mapstream.cpp's
    // mapstreamfail()/done path) - so the loop above can already have
    // observed and printed this exact final text while state still read
    // MS_ACTIVE, one iteration before breaking out here. Dedupe against
    // lasttext (mirrors the fix in mapstream.cpp's mapstreamwaitloop()) so
    // that race can never produce two identical "HARNESS: <outcome>" lines.
    const char *finaltext = mapstreamstatustext();
    if(strcmp(finaltext, lasttext)) printf("HARNESS: %s\n", finaltext);
    printf("HARNESS: RESULT state=%s elapsed_ms=%u\n",
           state == MS_DONE ? "MS_DONE" : state == MS_FAILED ? "MS_FAILED" : "MS_OTHER",
           (unsigned)totalelapsed);
    fflush(stdout);
    return 0;
}
