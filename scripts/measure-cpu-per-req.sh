#!/usr/bin/env bash
set -u
LOGDIR=/home/ystyle/Projects/Cangjie/.scratch/logs
CLK=$(getconf CLK_TCK)
run() {
  local name="$1" dir="$2" port="$3"
  pkill -f 'bench-stdx-min/target' 2>/dev/null
  pkill -f 'bench-tachyon-min/target' 2>/dev/null
  sleep 1
  eval "$(cjvs env zsh)" >/dev/null 2>&1
  eval "$(cjvs stdx-env zsh)" >/dev/null 2>&1
  cd "$dir"
  ./target/release/bin/main "$port" > "$LOGDIR/cpu-$name.log" 2>&1 &
  local pid=$!
  for i in $(seq 1 80); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:$port/ && break; sleep 0.25; done
  /home/ystyle/Projects/Cangjie/.scratch/bench-go/bin/loadgen -url http://127.0.0.1:$port/ -conns 128 -warmup 2s -duration 3s > /dev/null 2>&1
  sleep 1
  local s1=$(awk '{print $14+$15}' /proc/$pid/stat)
  /home/ystyle/Projects/Cangjie/.scratch/bench-go/bin/loadgen -url http://127.0.0.1:$port/ -conns 128 -warmup 1s -duration 10s > "$LOGDIR/cpu-run-$name.json" 2>&1
  local s2=$(awk '{print $14+$15}' /proc/$pid/stat)
  local reqs=$(grep -o '"requests": [0-9]*' "$LOGDIR/cpu-run-$name.json" | head -1 | grep -o '[0-9]*')
  local qps=$(grep -o '"qps": [0-9.]*' "$LOGDIR/cpu-run-$name.json" | head -1 | grep -o '[0-9.]*')
  local rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status)
  echo "### $name"
  echo "  QPS             = $qps"
  echo "  requests        = $reqs"
  echo "  server CPU(s)   = $(python3 -c "print('%.2f' % (($s2-$s1)/$CLK))")  (CLK_TCK=$CLK)"
  echo "  CPU per request = $(python3 -c "print('%.0f ns' % (($s2-$s1)/$CLK/$reqs*1e9))")  (reqs=$reqs)"
  echo "  RSS             = $rss kB"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  sleep 2
}
run tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481
run stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480
run tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481
run stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480
echo DONE