# cangjie-runtime-issue-3577-repro

Cangjie runtime issue #3577 复现材料：SockRecvNonBlockGeneral 在 EAGAIN 后无条件 sched_yield 的 cjprof 采样数据、火焰图、压测脚本与 sched_yield 成本探针