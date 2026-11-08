补充复现材料（采样原始数据、火焰图、脚本、探针），已归档到两个公开仓：

- **GitHub**：<https://github.com/ystyle/cangjie-runtime-issue-3577-repro>
- **AtomGit（镜像）**：<https://atomgit.com/ystyle/cangjie-runtime-issue-3577-repro>
- **Gist**（只有文本文件）：<https://gist.github.com/ystyle/b6aeadae37efdd17efe62baab4183617>

## cjprof 采样原始数据

| 文件 | 说明 |
|---|---|
| [tachyon-prof.data](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/profiles/tachyon-prof.data) | 被测服务（纯 Cangjie HTTP/1.1，373,410 req/s，256 长连接）原始采样数据，161 KB |
| [tachyon-report.txt](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/profiles/tachyon-report.txt) | 上面数据的 `cjprof report` 完整输出（64 KB，含全部符号） |
| [flame-tachyon.svg](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/profiles/flame-tachyon.svg) | 火焰图（`cjprof report -F`） |
| [stdx-prof.data](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/profiles/stdx-prof.data) | 对照组 `stdx.net.http` 服务端（144,013 req/s）原始数据，615 KB |
| [stdx-report.txt](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/profiles/stdx-report.txt) | 对照组 report |
| [flame-stdx.svg](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/profiles/flame-stdx.svg) | 对照组火焰图 |

查看方式（需 Cangjie SDK）：

```shell
cjprof report -i tachyon-prof.data      # 文本
cjprof report -F -i tachyon-prof.data   # 生成 FlameGraph.svg
```

## 采集与压测脚本

- [prof-tachyon.sh](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/scripts/prof-tachyon.sh)：容器内采样单个服务的完整流程（含 `-f 499` 与 `timeout -s INT` 落盘）
- [prof-both.sh](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/scripts/prof-both.sh)：同时采样两个服务并导出火焰图
- [win-bench.sh](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/scripts/win-bench.sh) / [rate-cmp.sh](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/scripts/rate-cmp.sh) / [bomb-cmp.sh](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/scripts/bomb-cmp.sh)：跨机压测、定速对比、吞吐上限对比

## `sched_yield` 单次成本探针

[sched_yield_cost.c](https://raw.githubusercontent.com/ystyle/cangjie-runtime-issue-3577-repro/main/probe/sched_yield_cost.c)

```shell
gcc -O2 -o y sched_yield_cost.c -lpthread
./y 1 2000     # 单线程：约 487 ns/op
```

## 补充说明

- 采样在 privileged 容器内完成（宿主机 sudo 受 no-new-privileges 限制，`perf_event_paranoid=2`）。
- `cjprof record -f 999` 采样开销过大（吞吐从 37 万跌到 116 req/s），因此用 `-f 499`。
- 按 profile 的 16.7% × 5 核 ÷ 373,410 req/s ≈ 2.2 µs/请求落在 `sched_yield`，
  除以 487 ns/次 ≈ **4~5 次/请求**，说明自旋分支确实在触发，不只是"退出前那一次"。
