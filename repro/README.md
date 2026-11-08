# Cangjie/UsersForum #3577 最小复现

对应 issue：<https://atomgit.com/Cangjie/UsersForum/issues/3577>

复现目标：高并发 TCP 服务端在 `std.net` 读路径上，每次 `EAGAIN` 都会执行
`sched_yield()`（`runtime/src/CJThread/src/aio/sock/src/sock.cpp:1634`
`SockRecvNonBlockGeneral`），在 cjprof 里表现为 `sched_yield` 自采样占比居高不下。

本工程**只用 `std.*`，不依赖 stdx**，自带压测客户端，不需要外部压测工具。

## 一键复现

```shell
eval "$(cjvs env zsh)"
cd repro
./run-repro.sh 128 20 499     # [连接数] [压测秒数] [采样频率]
```

脚本会：编译 → 起服务端 → `cjprof record -p` 采样 → 纯仓颉客户端施压 → 打印热点。

## 手动分步

```shell
eval "$(cjvs env zsh)"
cjpm build -j 8

# 终端 1：服务端
./target/release/bin/main server 18080

# 终端 2：采样（-f 499；999 采样开销过大会显著压低吞吐）
SERVER_PID=$(pgrep -f 'main server 18080')
cjprof record -f 499 -p "$SERVER_PID" -o repro-prof.data

# 终端 3：施压 128 连接 x 20 秒
./target/release/bin/main client 127.0.0.1 18080 128 20

# 采样本终止后
cjprof report -i repro-prof.data | head -30
cjprof report -F -i repro-prof.data      # 生成 FlameGraph.svg
```

## 本机实测（Ryzen 7 7840HS，8C/16T）

- 纯仓颉客户端 128 连接：**约 63~67 万 req/s，0 错误**
- 服务端平均占用约 6 核
- profile 中 `sched_yield` 的 self 占比 **16.72%**：

```
Children        Self    Symbol
  43.28%       1.12%    CJ_MRT_SockRecvNonBlock
  24.82%       1.92%    CJ_MRT_SockRecvNonBlockGeneral
  16.72%      16.72%    sched_yield
```

（本仓 `../profiles/` 下是同一现象在真实 HTTP 服务端上的采样数据与火焰图。）

## 无 root 权限时

`cjprof` 依赖 `perf_event_open`，在 `perf_event_paranoid=2` 且没有 root 的机器上采不到数据。
可以把“构建 + 运行 + 采样”整体放进 privileged 容器：

```shell
docker run --rm -it --privileged --security-opt seccomp=unconfined \
  --network host -v "$HOME/.config/cjvs/store/1.2.0:/cj:ro" -v "$PWD/..:/src" \
  -e LD_LIBRARY_PATH=/cj/tools/lib:/cj/runtime/lib/linux_x86_64_cjnative:/cj/lib/linux_x86_64_cjnative \
  <任意带 glibc 的基础镜像> sh -c 'cd /src/repro && /cj/bin/cjc --version && ./run-repro.sh'
```

> 注意：容器内 `cjpm` 需要可写的 `target/`；如果仓目录是只读挂载，先把工程拷到容器内的可写目录。

## 目录

```
repro/
  cjpm.toml
  src/main.cj       服务端 + 客户端（单文件，约 200 行）
  run-repro.sh      一键复现脚本
  README.md
```
