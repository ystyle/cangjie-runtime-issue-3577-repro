#!/usr/bin/env bash
set -u
LOGDIR=/home/ystyle/Projects/Cangjie/.scratch/logs
CLK=$(getconf CLK_TCK)
SSH="ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null lxy52@192.168.3.231"
LOCAL_IP=192.168.3.6

run() {
  local name="$1" dir="$2" port="$3" conns="$4" dur="$5"
  pkill -f 'bench-stdx-min/target' 2>/dev/null; pkill -f 'bench-tachyon-min/target' 2>/dev/null
  sleep 1
  eval "$(cjvs env zsh)" >/dev/null 2>&1; eval "$(cjvs stdx-env zsh)" >/dev/null 2>&1
  ( cd "$dir" && exec ./target/release/bin/main "$port" ) > "$LOGDIR/linux-srv-$name.log" 2>&1 &
  local pid=$!
  for i in $(seq 1 80); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:$port/ && break; sleep 0.25; done
  local s1=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0)
  $SSH "cd C:/Users/lxy52 && bombardier.exe -c $conns -d $dur -l --fasthttp http://$LOCAL_IP:$port/" > "$LOGDIR/winsrc-$name-$conns.txt" 2>&1
  local s2=$(awk '{print $14+$15}' /proc/$pid/stat 2>/dev/null || echo 0)
  local rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null || echo -1)
  local reqs=$(grep -oE 'Requests: *[0-9]+' "$LOGDIR/winsrc-$name-$conns.txt" | head -1 | grep -oE '[0-9]+')
  echo "### $name  conns=$conns  (压测机=9950X3D/32T → 被测机 7840HS/16T)"
  grep -E 'Reqs/sec|Latency  |^ +50%|^ +99%' "$LOGDIR/winsrc-$name-$conns.txt" | sed 's/^/    /'
  python3 -c "
ticks=$s2-$s1; reqs=${reqs:-0}; clk=$CLK
cpu=ticks/clk
print('    server CPU=%.1fs  CPU/req=%s  RSS=%s kB' % (cpu, ('%.0f ns' % (cpu/reqs*1e9)) if reqs else 'n/a', '$rss'))
"
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  echo ""
  sleep 2
}

for c in 128 256; do
  run tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481 $c 20s
  run stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480 $c 20s
  run tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min 27481 $c 20s
  run stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min    27480 $c 20s
done
echo DONE