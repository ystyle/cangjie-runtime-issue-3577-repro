# Cangjie/UsersForum #3577 复现材料

对应 issue：<https://atomgit.com/Cangjie/UsersForum/issues/3577>

> 主题：`SockRecvNonBlockGeneral` 在 `EAGAIN` 且不再自旋时仍执行 `sched_yield()`，
> 高并发 HTTP 服务端约 17% 的每请求 CPU 消耗在这里。

## 目录

### `profiles/` — cjprof 采样原始数据

| 文件 | 说明 |
|---|---|
| `tachyon-prof.data` | 被测服务（纯 Cangjie HTTP/1.1 服务端，373,410 req/s，256 长连接）的 cjprof 原始数据 |
| `tachyon-report.txt` | 上面数据的 `cjprof report` 文本输出（完整符号列表） |
| `flame-tachyon.svg` | 上面数据的火焰图（`cjprof report -F`） |
| `stdx-prof.data` | 对照组：`stdx.net.http` 服务端（144,013 req/s）的原始数据 |
| `stdx-report.txt` | 对照组 report |
| `flame-stdx.svg` | 对照组火焰图 |

**查看方式**（需要 Cangjie SDK）：

```shell
cjprof report -i tachyon-prof.data        # 文本
cjprof report -F -i tachyon-prof.data     # 生成 FlameGraph.svg
```

关键数据点（tachyon-profile）：

```
Children        Self    Symbol
  43.28%       1.12%    CJ_MRT_SockRecvNonBlock
  24.82%       1.92%    CJ_MRT_SockRecvNonBlockGeneral
  16.72%      16.72%    sched_yield          ← 本条 issue 的主题
```

采集命令（宿主机 sudo 不可用，在 privileged 容器内完成）：

```shell
cjprof record -f 499 -p <pid> -o prof.data   # 采样 10 s，期间由另一台机器施压
```

> 注意：`-f 999` 采样开销过大（吞吐从 37 万跌到 116 req/s），故用 499 Hz。

### `scripts/` — 压测与采集脚本

| 文件 | 说明 |
|---|---|
| `prof-tachyon.sh` | 容器内 cjprof 采样单个服务的完整流程 |
| `prof-both.sh` | 同时采样 tachyon 与 stdx.net.http 并导出火焰图 |
| `win-bench.sh` / `win-bench2.sh` | 压测器在另一台 Windows 机器上（128/256/512/1024 连接）跨机压测 |
| `rate-cmp.sh` | 定速（同一输入速率）对比 |
| `bomb-cmp.sh` | 吞吐上限对比（bombardier） |
| `measure-cpu-per-req.sh` | 用 `/proc/<pid>/stat` 统计服务端每请求 CPU |
| `k6-hello-cmp.js` | k6 对照脚本 |

脚本里的路径是作者本机路径，按需修改；核心命令都是通用的。

### `probe/sched_yield_cost.c` — `sched_yield` 单次成本测量

```shell
gcc -O2 -o y sched_yield_cost.c -lpthread
./y 1 2000     # 单线程：约 487 ns/op
./y 8 2000     # 8 线程同时 yield（不具代表性，仅供对照）
```

## 环境

- Cangjie 1.2.0（cjnative，x86_64-unknown-linux-gnu）
- 被测机：AMD Ryzen 7 7840HS（8C/16T），Linux，2.5GbE
- 压测机：AMD Ryzen 9 9950X3D（16C/32T），Windows 10，bombardier（fasthttp 客户端）
- runtime 源码核对：`release/1.2`（HEAD `8e6100a`，v1.2.1）与 `main`（`e927f24`）
  在 `sock.cpp` / `sock_impl.h` 上 `git diff` 为空

## 被测服务

一个不使用 stdx、只依赖 `std.*` 的 HTTP/1.1 服务端（tachyon），handler 只回 `200 Hello, World!`。
profile 显示服务端自身业务代码（解析/序列化/reset）合计约 10%，
其余主要是 socket 读路径（60%）与写路径（11%）。
