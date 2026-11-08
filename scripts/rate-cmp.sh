#!/usr/bin/env bash
set -u
LOGDIR=/home/ystyle/Projects/Cangjie/.scratch/logs
B=/home/ystyle/Projects/Cangjie/.scratch/loadtools
CLK=$(getconf CLK_TCK)
ulimit -n 65535 2>/dev/null || true
wait_load() { for i in $(seq 1 40); do local l=$(cut -d' ' -f1 /proc/loadavg); if [ "${l%.*}" -lt 6 ]; then return 0; fi; sleep 3; done; }

run_rate() {
  local name="$1" dir="$2" port="$3" rate="$4"
  local tag="$name-$rate"
  pkill -f 'bench-stdx-min/target' 2>/dev/null; pkill -f 'bench-tachyon-min/target' 2>/dev/null
  sleep 1; wait_load
  eval "$(cjvs env zsh)" >/dev/null 2>&1; eval "$(cjvs stdx-env zsh)" >/dev/null 2>&1
  ( cd "$dir" && exec ./target/release/bin/main "$port" ) > "$LOGDIR/rate-srv-$tag.log" 2>&1 &
  local pid=$!
  for i in $(seq 1 80); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:$port/ && break; sleep 0.25; done
  local s1=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0)
  "$B/bombardier" -c 128 -r "$rate" -d 10s -l --fasthttp "http://127.0.0.1:$port/" > "$LOGDIR/rate-$tag.txt" 2>&1
  local s2=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0)
  echo "### $name  目标速率 ${rate}/s  (loadavg $(cut -d' ' -f1 /proc/loadavg))"
  grep -E 'Reqs/sec|Latency  |^\s+50%|^\s+99%|HTTP codes' "$LOGDIR/rate-$tag.txt" | sed 's/^/    /'
  grep -A3 'HTTP codes' "$LOGDIR/rate-$tag.txt" | tail -3 | sed 's/^/    /'
  echo "    server CPU total: $(python3 -c "print('%.1f s' % (($s2-$s1)/$CLK))") / 10s"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo ""
  sleep 2
}

for rate in 200000 350000 500000; do
  run_rate tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481 $rate
  run_rate stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480 $rate
done
echo DONE