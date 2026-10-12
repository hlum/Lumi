#!/bin/sh
# Push the bench photos to the phone or pull the rendered contact sheets back. Usage: scripts/bench.sh push|pull
set -e
DEV=${LUMI_DEVICE:-B9FF212E-4C23-55C1-900D-5935FF7BE96D}
APP=com.hlum.lumi
cd "$(dirname "$0")/../bench"
case "$1" in
  push) for f in *.jpg; do xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer --domain-identifier "$APP" --source "$f" --destination "Documents/bench/$f" >/dev/null; done; echo 1 > /tmp/lumi_bench_RUN && xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer --domain-identifier "$APP" --source /tmp/lumi_bench_RUN --destination Documents/bench/RUN >/dev/null
        echo "pushed $(ls *.jpg | wc -l) photos; bench armed (pull disarms)" ;;
  pull) mkdir -p out
        for f in $(xcrun devicectl device info files --device "$DEV" --domain-type appDataContainer --domain-identifier "$APP" --subdirectory Documents/bench_out 2>/dev/null | grep -o '[A-Za-z0-9_]*\.jpg'); do
          xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer --domain-identifier "$APP" --source "Documents/bench_out/$f" --destination "out/$f" >/dev/null; done
        echo 0 > /tmp/lumi_bench_RUN && xcrun devicectl device copy to --device "$DEV" --domain-type appDataContainer --domain-identifier "$APP" --source /tmp/lumi_bench_RUN --destination Documents/bench/RUN >/dev/null
        ls out ;;
  *) echo "usage: $0 push|pull"; exit 1 ;;
esac
