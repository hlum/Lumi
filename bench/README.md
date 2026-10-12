# Quality bench (Phase Q0)

Photos used to judge face, body and makeup quality on the device. All from Wikimedia Commons under free licences; sources in `SOURCES.json`. Not bundled in the app.

- `scripts/bench.sh push` copies them to the app's Documents/bench on the phone.
- Run `QualityBenchTests` on the device; it writes contact sheets to Documents/bench_out.
- `scripts/bench.sh pull` copies the sheets to `bench/out/` (ignored by git).
