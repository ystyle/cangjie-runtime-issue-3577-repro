/*
 * Cangjie/UsersForum #3577 最小复现
 *
 * 复现目标：高并发 TCP 服务端在 std.net 读路径上，每次 EAGAIN 都会执行 sched_yield()，
 * 在 cjprof 里表现为 sched_yield 的自采样占比居高不下（本次环境 16.7%）。
 *
 * 用法：
 *   ./repro server <port>                 # 服务端
 *   ./repro client <host> <port> <conns> <seconds>   # 纯仓颉压测客户端
 *
 * 不依赖 stdx，只用 std.*。
 */
package sched_yield_repro

import std.net.{TcpSocket, TcpServerSocket}
import std.sync.{AtomicBool, AtomicInt64}
import std.time.MonoTime
import std.core.*

// 固定响应：HTTP/1.1 200 + Content-Length: 2 + "OK"（共 40 字节）
let RESPONSE: String = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
let REQUEST: String = "GET / HTTP/1.1\r\nHost: x\r\n\r\n"
// 响应里 "\r\n\r\n" 之后还有 2 字节 body
let RESPONSE_HEAD_END: Int64 = 34
let RESPONSE_TOTAL: Int64 = 40

main(args: Array<String>): Int32 {
    if (args.size < 2) {
        println("usage:")
        println("  repro server <port>")
        println("  repro client <host> <port> <conns> <seconds>")
        return 2
    }
    match (args[0]) {
        case "server" => return runServer(parseU16(args[1]))
        case "client" =>
            if (args.size < 5) {
                println("client 需要 <host> <port> <conns> <seconds>")
                return 2
            }
            return runClient(args[1], parseU16(args[2]), parseInt(args[3]), parseInt(args[4]))
        case _ =>
            println("未知子命令: " + args[0])
            return 2
    }
}

// ---------------- 服务端 ----------------

func runServer(port: UInt16): Int32 {
    let srv = TcpServerSocket(bindAt: port)
    srv.reuseAddress = true
    srv.bind()
    println("listening on 0.0.0.0:" + port.toString())

    let running = AtomicBool(true)
    while (running.load()) {
        let conn = try {
            srv.accept()
        } catch (e: Exception) {
            continue
        }
        spawn {
            serveConn(conn)
        }
    }
    srv.close()
    return 0
}

/** 每个连接一个协程：读请求 -> 回固定响应，keep-alive 循环 */
func serveConn(conn: TcpSocket): Unit {
    let buf = Array<Byte>(4096, repeat: 0)
    let resp = RESPONSE.toArray()
    try {
        while (true) {
            let n = conn.read(buf)
            if (n <= 0) {
                break
            }
            conn.write(resp)
        }
    } catch (e: Exception) {
        // 连接断开
    }
    try {
        conn.close()
    } catch (e: Exception) {
        ()
    }
}

// ---------------- 客户端 ----------------

func runClient(host: String, port: UInt16, conns: Int64, seconds: Int64): Int32 {
    let deadline = MonoTime.now() + Duration.second * seconds
    let okCount = AtomicInt64(0)
    let errCount = AtomicInt64(0)
    let req = REQUEST.toArray()

    var i: Int64 = 0
    while (i < conns) {
        spawn {
            clientWorker(host, port, req, deadline, okCount, errCount)
        }
        i += 1
    }
    // 等所有 worker 结束：简单按时间轮询（worker 自身到 deadline 退出）
    sleep(Duration.second * (seconds + 2))

    let ok = okCount.load()
    let err = errCount.load()
    let secs = Float64(seconds)
    println("requests=" + ok.toString() + " errors=" + err.toString() +
            " rps=" + (Float64(ok) / secs).toString())
    return 0
}

func clientWorker(host: String, port: UInt16, req: Array<Byte>, deadline: MonoTime,
                  okCount: AtomicInt64, errCount: AtomicInt64): Unit {
    let conn = TcpSocket(host, port)
    try {
        conn.connect()
    } catch (e: Exception) {
        errCount.fetchAdd(1)
        return
    }
    let buf = Array<Byte>(4096, repeat: 0)
    while (MonoTime.now() < deadline) {
        try {
            conn.write(req)
            var got: Int64 = 0
            while (got < RESPONSE_TOTAL) {
                let n = conn.read(buf[got..RESPONSE_TOTAL])
                if (n <= 0) {
                    throw Exception("closed")
                }
                got += n
            }
            // "HTTP/1.1 200 ..." 的第 10 个字节（index 9）是 '2'
            if (got == RESPONSE_TOTAL && buf[9] == 50) {
                okCount.fetchAdd(1)
            } else {
                errCount.fetchAdd(1)
            }
        } catch (e: Exception) {
            errCount.fetchAdd(1)
            break
        }
    }
    try {
        conn.close()
    } catch (e: Exception) {
        ()
    }
}

// ---------------- 参数解析 ----------------

func parseU16(s: String): UInt16 {
    var v: Int64 = 0
    for (b in s.toArray()) {
        if (b >= 48 && b <= 57) {
            v = v * 10 + Int64(b) - 48
        }
    }
    return UInt16(v)
}

func parseInt(s: String): Int64 {
    var v: Int64 = 0
    for (b in s.toArray()) {
        if (b >= 48 && b <= 57) {
            v = v * 10 + Int64(b) - 48
        }
    }
    return v
}