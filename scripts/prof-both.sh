#!/usr/bin/env bash
set -u
LOGDIR=/home/ystyle/Projects/Cangjie/.scratch/logs
CJ=$HOME/.config/cjvs/store/1.2.0
LIB='/cj/tools/lib:/cj/runtime/lib/linux_x86_64_cjnative:/cj/lib/linux_x86_64_cjnative'
SSH="ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null lxy52@192.168.3.231"

prof() {
  local name="$1" bin="$2" port="$3"
  echo "===== $name ====="
  docker rm -f prof-$name >/dev/null 2>&1
  docker run -d --name prof-$name --privileged --security-opt seccomp=unconfined \
    --network host -u root -v $CJ:/cj:ro -v $bin:/app:ro -e LD_LIBRARY_PATH=$LIB \
    cjreg:latest sh -c 'sleep 600' >/dev/null
  docker exec -d prof-$name sh -c "mkdir -p /work && cd /work && exec /app/main $port"
  for i in $(seq 1 80); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:$port/ && break; sleep 0.25; done
  local pid=$(docker exec prof-$name sh -c 'pgrep -x main' | head -1 | tr -d '\r')
  $SSH "cd C:/Users/lxy52 && bombardier.exe -c 256 -d 16s -l --fasthttp http://192.168.3.6:$port/" > $LOGDIR/pf-$name-load.txt 2>&1 &
  local lp=$!
  sleep 3
  docker exec prof-$name sh -c "cd /work && timeout -s INT 10 /cj/tools/bin/cjprof record -f 999 -p $pid -o /work/prof.data" > $LOGDIR/pf-$name-rec.log 2>&1
  wait $lp 2>/dev/null || true
  grep -E 'Reqs/sec|^ +99%' $LOGDIR/pf-$name-load.txt | sed 's/^/  /'
  docker exec prof-$name sh -c "cd /work && LD_LIBRARY_PATH=$LIB /cj/tools/bin/cjprof report -i /work/prof.data" > $LOGDIR/pf-$name-report.txt 2>&1
  docker exec prof-$name sh -c "cd /work && LD_LIBRARY_PATH=$LIB /cj/tools/bin/cjprof report -F -i /work/prof.data" >/dev/null 2>&1
  docker cp prof-$name:/work/FlameGraph.svg $LOGDIR/flame-$name.svg 2>/dev/null && echo '  flamegraph 已导出'
  docker cp prof-$name:/work/prof.data $LOGDIR/$name-prof.data 2>/dev/null
  echo '  --- top self 时间 ---'
  head -30 $LOGDIR/pf-$name-report.txt | sed 's/^/    /'
  docker rm -f prof-$name >/dev/null 2>&1
}

prof tachyon /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min/target/release/bin 27481
prof stdx    /home/ystyle/Projects/Cangjie/.scratch/bench-stdx-min/target/release/bin    27480
echo DONE