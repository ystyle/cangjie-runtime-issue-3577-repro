#!/usr/bin/env bash
set -u
LOGDIR=/home/ystyle/Projects/Cangjie/.scratch/logs
CJ=$HOME/.config/cjvs/store/1.2.0
LIB='/cj/tools/lib:/cj/runtime/lib/linux_x86_64_cjnative:/cj/lib/linux_x86_64_cjnative'
SSH="ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null lxy52@192.168.3.231"
docker rm -f proft >/dev/null 2>&1
docker run -d --name proft --privileged --security-opt seccomp=unconfined \
  --network host -u root -v $CJ:/cj:ro \
  -v /home/ystyle/Projects/Cangjie/.scratch/bench-tachyon-min/target/release/bin:/app:ro \
  -e LD_LIBRARY_PATH=$LIB cjreg:latest sh -c 'sleep 600' >/dev/null
docker exec -d proft sh -c 'mkdir -p /work && cd /work && exec /app/main 27481'
for i in $(seq 1 80); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:27481/ && break; sleep 0.25; done
PID=$(docker exec proft sh -c 'pgrep -x main' | head -1 | tr -d '\r')
echo "pid=$PID"
$SSH "cd C:/Users/lxy52 && bombardier.exe -c 256 -d 16s -l --fasthttp http://192.168.3.6:27481/" > $LOGDIR/pt-load.txt 2>&1 &
LP=$!
sleep 3
docker exec proft sh -c "cd /work && timeout -s INT 10 /cj/tools/bin/cjprof record -f 499 -p $PID -o /work/prof.data" 2>&1 | head -5
wait $LP 2>/dev/null || true
grep -E 'Reqs/sec|^ +99%' $LOGDIR/pt-load.txt | sed 's/^/  /'
docker exec proft sh -c 'ls -la /work/prof.data'
docker exec proft sh -c "cd /work && LD_LIBRARY_PATH=$LIB /cj/tools/bin/cjprof report -i /work/prof.data" > $LOGDIR/pt-report.txt 2>&1
echo '=== tachyon profile top ==='
head -40 $LOGDIR/pt-report.txt
docker exec proft sh -c "cd /work && LD_LIBRARY_PATH=$LIB /cj/tools/bin/cjprof report -F -i /work/prof.data" >/dev/null 2>&1
docker cp proft:/work/FlameGraph.svg $LOGDIR/flame-tachyon.svg 2>/dev/null && echo 'flame 已导出'
docker cp proft:/work/prof.data $LOGDIR/tachyon-prof2.data 2>/dev/null
docker rm -f proft >/dev/null 2>&1
echo DONE