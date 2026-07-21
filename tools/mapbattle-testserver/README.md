# MAPBATTLE test server

A local replica of the RUGBY-family intermission map-vote flow, for testing the
SwiftGibs map-vote panel without waiting for real 10-minute matches.

What it reproduces (captured from live traffic 2026-07-21):

- 1-minute matches (`mbtestminutes`), then a 25s intermission vote
- the announcement and candidates sent as ONE batched multi-line message
  (this batching is what broke the first panel release - keep it that way)
- players vote by saying 1/2/3 in chat; the server eats the message and
  broadcasts a full tally line ending "(Voted by <name>)"
- `WINNER >> <map> (<n> votes)` then the map changes to the winner

Run it: `tools/mapbattle-testserver/run-testserver.sh`
Join it: `/connect localhost 28885` (from Windows against WSL, plain
`localhost` works on current Windows; otherwise use the WSL IP from `hostname -I`).

Not part of any shipped bundle - the patch applies only to the scratch build tree.
