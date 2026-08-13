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

#include "cube.h"
#include "mapstream.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    if(argc < 2)
    {
        fprintf(stderr, "usage: %s <mapname> [cancel-after-ms]\n", argv[0]);
        return 2;
    }
    const char *name = argv[1];
    int cancelafter = argc > 2 ? atoi(argv[2]) : 0;

    const char *url = getenv("MAPSTREAM_TEST_URL");
    if(url && url[0]) mapstreamurl = newstring(url);

    loadmapmanifest();
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
