// harness-stubs.cpp: minimal engine-symbol stubs for the mapstream
// standalone test harness. Task 5's brief pre-authorizes exactly this list
// (conoutf, findfile, storage paths) as a fallback route when the real
// engine client cannot boot headless in this environment - see
// task-5-report.md. Everything else mapstream.cpp/sghttp.cpp/sgsha256.cpp
// touch is either standard libc, real SDL2 (linked normally, not stubbed),
// or header-only cube helpers (shared/tools.h) - not stubbed here because
// nothing needs to be.
//
// findfile()/openrawfile()/openfile() reproduce the REAL engine's behavior
// for the "no homedir set" case (shared/stream.cpp: with homedir[0]==0,
// findfile(rel, "w"/"a") returns the relative name unchanged, and
// openrawfile() just fopen()s the resolved name) - CWD-relative, which is
// exactly the mode the test script runs the harness in (its own scratch
// directory). The packagedirs search-path / homedir-prefix machinery the
// real findfile() also has is not reproduced: this harness never reads an
// existing file through it, only checks existence ('e') and writes
// ('w'/'a'), both of which behave identically to the real function in this
// mode.

#include "cube.h"
#include "mapstream.h"

#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <sys/stat.h>

// --- console -------------------------------------------------------------

void conoutfv(int type, const char *fmt, va_list args)
{
    (void)type;
    vprintf(fmt, args);
    printf("\n");
    fflush(stdout);
}

void conoutf(const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    conoutfv(CON_INFO, fmt, args);
    va_end(args);
}

void conoutf(int type, const char *fmt, ...)
{
    va_list args; va_start(args, fmt);
    conoutfv(type, fmt, args);
    va_end(args);
}

void conoutf(int type, int tag, const char *fmt, ...)
{
    (void)tag;
    va_list args; va_start(args, fmt);
    conoutfv(type, fmt, args);
    va_end(args);
}

// --- storage paths ---------------------------------------------------------

static void harnessmkdirs(char *path)
{
    char *dir = strchr(path[0] == '/' ? path+1 : path, '/');
    while(dir)
    {
        *dir = '\0';
        mkdir(path, 0777); // best-effort, same spirit as the real createdir() callers - EEXIST etc ignored
        *dir = '/';
        dir = strchr(dir+1, '/');
    }
}

// `stream` declares size()/getline()/printf() as virtual but WITHOUT an
// inline body (real bodies live in shared/stream.cpp, not compiled here) -
// under the Itanium C++ ABI's "key function" rule, that makes whichever TU
// defines the first of those the home for stream's vtable object itself
// (needed even just to run stream's base-subobject constructor/destructor
// inside a harnessfilestream - link fails with "undefined reference to
// vtable for stream" otherwise, found empirically). harnessfilestream
// (below) overrides all three with real, actually-used bodies, so these
// never run - they exist purely to give the vtable a home.
stream::offset stream::size() { return -1; }
bool stream::getline(char *, size_t) { return false; }
size_t stream::printf(const char *, ...) { return 0; }

const char *findfile(const char *filename, const char *mode)
{
    static string s;
    copystring(s, filename);
    if(mode[0] == 'w' || mode[0] == 'a')
    {
        harnessmkdirs(s);
        return s;
    }
    struct stat st;
    if(stat(s, &st) == 0) return s;
    return NULL;
}

struct harnessfilestream : stream
{
    FILE *file;
    harnessfilestream() : file(NULL) {}
    ~harnessfilestream() { close(); }

    bool open(const char *name, const char *mode) { file = fopen(name, mode); return file != NULL; }
    void close() { if(file) { fclose(file); file = NULL; } }
    bool end() { return file ? feof(file) != 0 : true; }

    // size()/getline()/printf() have no inline body on the base `stream`
    // (defined out-of-line in shared/stream.cpp, which this harness does
    // not compile) - overridden here so the vtable never needs that TU.
    offset size()
    {
        if(!file) return 0;
        long cur = ftell(file);
        fseek(file, 0, SEEK_END);
        long sz = ftell(file);
        fseek(file, cur, SEEK_SET);
        return sz;
    }
    bool getline(char *str, size_t len)
    {
        if(!file || !fgets(str, (int)len, file)) { if(str && len) str[0] = '\0'; return false; }
        size_t n = strlen(str);
        while(n > 0 && (str[n-1] == '\n' || str[n-1] == '\r')) str[--n] = '\0';
        return true;
    }
    size_t printf(const char *, ...) { return 0; } // unused by this harness

    size_t read(void *buf, size_t len) { return file ? fread(buf, 1, len, file) : 0; }
    size_t write(const void *buf, size_t len) { return file ? fwrite(buf, 1, len, file) : 0; }
    bool flush() { return file ? !fflush(file) : false; }
};

stream *openrawfile(const char *filename, const char *mode)
{
    const char *resolved = findfile(filename, mode);
    if(!resolved) resolved = filename;
    harnessfilestream *f = new harnessfilestream;
    if(!f->open(resolved, mode)) { delete f; return NULL; }
    return f;
}

stream *openfile(const char *filename, const char *mode)
{
    return openrawfile(filename, mode);
}

// --- cube scripting registration (ICOMMAND/SVARP) --------------------------
// Never actually invoked by this harness (it calls mapstreambegin() etc.
// directly) - these just need to be linkable, since the ICOMMAND/SVARP
// macro expansions in mapstream.cpp emit real, address-taken functions
// regardless of whether the interpreter that would call them exists here.

bool addcommand(const char *name, identfun fun, const char *narg)
{
    (void)name; (void)fun; (void)narg;
    return true;
}

char *svariable(const char *name, const char *cur, char **storage, identfun fun, int flags)
{
    (void)name; (void)storage; (void)fun; (void)flags;
    return newstring(cur);
}

// --- debug-UI hook used only by mapstreamwaitloop()'s ICOMMAND -----------
// (not called by this harness's own poll loop in harness-main.cpp, but
// still needs a linkable definition - see the addcommand note above.)

void renderprogress(float bar, const char *text, GLuint tex, bool background)
{
    (void)bar; (void)text; (void)tex; (void)background;
}
