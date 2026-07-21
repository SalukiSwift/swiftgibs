#!/usr/bin/env bash
# Launch a Sauerbraten client for HEADLESS harness testing: no window, and
# crucially NO AUDIO DEVICE (SDL dummy driver) - under WSLg, sound would
# otherwise blast out of the Windows speakers on every test run.
# Usage: tools/headless-client.sh <client-binary> <args...>
exec env SDL_VIDEODRIVER=offscreen SDL_AUDIODRIVER=dummy "$@"
