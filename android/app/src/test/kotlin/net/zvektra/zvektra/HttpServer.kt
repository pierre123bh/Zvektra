package net.zvektra.zvektra

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.InputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.net.URI
import kotlin.concurrent.thread

/** Small loopback HTTP fixture using APIs available on the Android unit-test classpath. */
internal class HttpServer private constructor(private val socket: ServerSocket) {
    companion object {
        fun create(address: InetSocketAddress, @Suppress("UNUSED_PARAMETER") backlog: Int): HttpServer {
            val socket = ServerSocket(); socket.bind(address); return HttpServer(socket)
        }
    }
    val address get() = InetSocketAddress("127.0.0.1", socket.localPort)
    private var handler: ((Exchange) -> Unit)? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    fun createContext(@Suppress("UNUSED_PARAMETER") path: String, callback: (Exchange) -> Unit) { handler = callback }
    fun start() {
        running = true
        worker = thread(isDaemon = true) {
            while (running) {
                val client = try { socket.accept() } catch (_: SocketException) { break }
                client.use {
                    client.soTimeout = 5000
                    val input = client.getInputStream()
                    val first = line(input).split(' ')
                    val headers = mutableMapOf<String, String>()
                    while (true) {
                        val line = line(input)
                        if (line.isEmpty()) break
                        val parts = line.split(':', limit = 2)
                        if (parts.size == 2) headers[parts[0].lowercase()] = parts[1].trim()
                    }
                    val data = ByteArray(headers["content-length"]?.toInt() ?: 0)
                    var offset = 0
                    while (offset < data.size) {
                        val n = input.read(data, offset, data.size - offset)
                        check(n > 0); offset += n
                    }
                    val exchange = Exchange(client, URI(first[1]), data)
                    handler!!(exchange)
                    exchange.close()
                }
            }
        }
    }
    fun stop(@Suppress("UNUSED_PARAMETER") seconds: Int) {
        running = false; socket.close(); worker?.join(1000)
    }
    private fun line(input: InputStream): String {
        val output = ByteArrayOutputStream()
        while (true) {
            val next = input.read()
            if (next < 0 || next == 10) return output.toString("UTF-8").trimEnd('\r')
            output.write(next)
        }
    }
    class Headers : LinkedHashMap<String, String>() { fun add(key: String, value: String) { put(key, value) } }
    class Exchange(private val socket: Socket, val requestURI: URI, body: ByteArray) : Closeable {
        val requestBody = ByteArrayInputStream(body)
        val responseHeaders = Headers()
        private var status = 200
        private var sent = false
        val responseBody = object : ByteArrayOutputStream() { override fun close() { publish(toByteArray()) } }
        fun sendResponseHeaders(code: Int, @Suppress("UNUSED_PARAMETER") length: Long) { status = code }
        private fun publish(bytes: ByteArray) {
            if (sent) return
            sent = true
            val header = buildString {
                append("HTTP/1.1 $status Result\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n")
                responseHeaders.forEach { (key, value) -> append("$key: $value\r\n") }
                append("\r\n")
            }.toByteArray()
            socket.getOutputStream().apply { write(header); write(bytes); flush() }
        }
        override fun close() { if (!sent) publish(responseBody.toByteArray()) }
    }
}
