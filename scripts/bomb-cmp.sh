#!/usr/bin/env bash
set -u
LOGDIR=/home/ystyle/Projects/Cangjie/.scratch/logs
B=/home/ystyle/Projects/Cangjie/.scratch/loadtools
CLK=$(getconf CLK_TCK)
ulimit -n 65535 2>/dev/null || true

wait_load() { for i in $(seq 1 40); do local l=$(cut -d' ' -f1 /proc/loadavg); if [ "${l%.*}" -lt 6 ]; then return 0; fi; sleep 3; done; }

# 用 bombardier（wrk 风格，Go 实现，默认 fasthttp 客户端可选）做吞吐上限测试
run_bomb() {
  local name="$1" dir="$2" port="$3" conns="$4" dur="$5"
  pkill -f 'bench-stdx-min/target' 2>/dev/null; pkill -f 'bench-tachyon-min/target' 2>/dev/null
  sleep 1; wait_load
  eval "$(cjvs env zsh)" >/dev/null 2>&1; eval "$(cjvs stdx-env zsh)" >/dev/null 2>&1
  ( cd "$dir" && exec ./target/release/bin/main "$port" ) > "$LOGDIR/bomb-srv-$name.log" 2>&1 &
  local pid=$!
  for i in $(seq 1 80); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:$port/ && break; sleep 0.25; done
  local s1=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0)
  "$B/bombardier" -c "$conns" -d "$dur" -l --fasthttp "http://127.0.0.1:$port/" > "$LOGDIR/bomb-$name.txt" 2>&1 &
  local cpid=$!
  local c1=$(awk '{print $14+$15}' /proc/$cpid/stat 2>/dev/null || echo 0)
  wait $cpid
  local c2=$(awk '{print $14+$15}' /proc/$cpid/stat 2>/dev/null || echo 0)
  local s2=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0)
  local rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null || echo -1)
  local reqs=$(grep -oE 'Requests: *[0-9]+' "$LOGDIR/bomb-$name.txt" | head -1 | grep -oE '[0-9]+')
  local rps=$(grep -E 'Reqs/sec' "$LOGDIR/bomb-$name.txt" | head -1 | grep -oE '[0-9.]+')
  echo "### $name  conns=$conns  (loadavg $(cut -d' ' -f1 /proc/loadavg))"
  grep -E 'Statistics|Reqs/sec|Latency|99%|99.9%|HTTP codes' "$LOGDIR/bomb-$name.txt" | sed 's/^/    /'
  python3 - "$s1" "$s2" "$c2" "$CLK" "$rss" "$reqs" <<'PY'
import sys
s1,s2,c2,clk,rss,reqs=[int(x) for x in sys.argv[1:6]]
# c1/c2 是 bombardier 主进程，客户端还有线程但主进程 CPU 已能反映量级
cpu=(s2-s1)/clk
print('    server CPU=%.1fs  CPU/req=%s  RSS=%s kB' % (cpu, ('%.0f ns' % (cpu/reqs*1e9)) if reqs else 'n/a', rss))
PY
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo ""
  sleep 3
}

run_bomb tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481 128 20s
run_bomb stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480 128 20s
run_bomb tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481 128 20s
run_bomb stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480 128 20s
echo DONE