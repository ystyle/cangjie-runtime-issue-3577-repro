#!/usr/bin/env bash
# 一键复现：编译 → 起服务 → cjprof 采样 → 纯仓颉客户端施压 → 打印 profile 热点
#
# 用法：
#   ./run-repro.sh [连接数] [压测秒数] [采样频率]
# 默认：./run-repro.sh 128 20 499
#
# 前置：
#   1) eval "$(cjvs env zsh)"
#   2) cjprof 需要 perf_event 权限。若报权限错误，用 root 跑，或按 README 用 privileged 容器。
set -u
CONNS=${1:-128}
SECS=${2:-20}
FREQ=${3:-499}
PORT=18080
BIN=./target/release/bin/main
OUT=repro-prof.data

command -v cjprof >/dev/null 2>&1 || { echo "找不到 cjprof，请先 eval \"\$(cjvs env zsh)\""; exit 1; }

echo "== build =="
cjpm build -j 8 || exit 1

pkill -f "$BIN server" 2>/dev/null
sleep 0.5

echo "== start server =="
$BIN server $PORT > /tmp/repro-server.log 2>&1 &
SRV=$!
for i in $(seq 1 60); do curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" && break; sleep 0.2; done
if ! kill -0 $SRV 2>/dev/null; then
    echo "服务端启动失败："; cat /tmp/repro-server.log; exit 1
fi

echo "== cjprof record (freq=$FREQ, pid=$SRV) =="
cjprof record -f "$FREQ" -p $SRV -o $OUT > /tmp/repro-cjprof.log 2>&1 &
PROF=$!
sleep 2

echo "== client: $CONNS 连接 x $SECS 秒 =="
$BIN client 127.0.0.1 $PORT "$CONNS" "$SECS" | tail -2

sleep 1
kill -INT $PROF 2>/dev/null
wait $PROF 2>/dev/null
kill $SRV 2>/dev/null
wait $SRV 2>/dev/null

if [ ! -f "$OUT" ]; then
    echo "没有生成 $OUT，cjprof 日志："; head -5 /tmp/repro-cjprof.log
    exit 1
fi

echo
echo "== profile 热点（前 30 行）=="
REPORT=$(cjprof report -i "$OUT" 2>&1 | head -30)
echo "$REPORT"
if echo "$REPORT" | grep -q "No sampling data"; then
    cat <<'HINT'

没有采到数据 —— 通常是没有 perf_event 权限。两种解决方式：
  1) 用 root 运行本脚本；
  2) 或跑在 privileged 容器里（挂载仓颉 SDK，--privileged --network host），
     做法见同仓 README 的「无 root 权限时」一节。
HINT
fi
echo
echo "完整数据：$OUT"
echo "  cjprof report -i $OUT            # 文本"
echo "  cjprof report -F -i $OUT         # 生成 FlameGraph.svg"