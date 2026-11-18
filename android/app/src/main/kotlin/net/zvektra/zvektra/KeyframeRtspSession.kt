package net.zvektra.zvektra

import android.net.Uri
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/** Relays the existing RTSP/TCP session to request keyframes without real-time pacing. */
internal class KeyframeRtspSession(private val source: Uri) : AutoCloseable {
    private val loopback = InetAddress.getByName("127.0.0.1")
    private val host = requireNotNull(source.host)
    private val port = source.port.takeIf { it > 0 } ?: 554
    private val upstreamOrigin = "rtsp://${source.encodedAuthority!!.substringAfterLast('@')}"
    private val credentials = source.encodedUserInfo?.split(':', limit = 2)
    private val downstream = ServerSocket(0, 1, loopback)
    private val upstream = Socket()
    private val pathPrefix = "/${UUID.randomUUID()}"
    private val localOrigin = "rtsp://127.0.0.1:${downstream.localPort}$pathPrefix"
    private val plays = ConcurrentHashMap<String, Boolean>()
    @Volatile private var client: Socket? = null
    @Volatile private var challenge: String? = null
    @Volatile private var controlOrigin = upstreamOrigin
    @Volatile var playSent = false
        private set
    @Volatile var playReply = "no reply"
        private set

    val localUri: Uri = source.buildUpon().encodedAuthority(
        (source.encodedUserInfo?.let { "$it@" } ?: "") + "127.0.0.1:${downstream.localPort}"
    ).encodedPath(pathPrefix + source.encodedPath.orEmpty()).build()

    init {
        worker {
            downstream.use {
                val incoming = it.accept()
                client = incoming
                incoming.tcpNoDelay = true
                upstream.connect(InetSocketAddress(host, port), 6000)
                upstream.tcpNoDelay = true
                worker { relay(incoming, upstream, ::rewriteRequest) }
                relay(upstream, incoming, ::rewriteResponse)
            }
        }
    }

    private fun worker(block: () -> Unit) {
        Thread {
            try {
                block()
            } catch (_: IOException) {
                // The caller uses the capture result to decide whether to retry.
            } finally {
                close()
            }
        }.apply { isDaemon = true }.start()
    }

    private fun rewriteRequest(message: Message) {
        val request = message.first.split(' ', limit = 3)
        if (request.size != 3) return
        val (method, inboundTarget, version) = request
        val localTarget = Uri.parse(inboundTarget)
        val path = localTarget.encodedPath.orEmpty()
        if (!path.startsWith("$pathPrefix/") && path != pathPrefix && inboundTarget != "*") {
            throw IOException("Invalid playback session")
        }
        val suffix = path.removePrefix(pathPrefix) +
            (localTarget.encodedQuery?.let { "?$it" } ?: "")
        val target = if (localTarget.host == "127.0.0.1") {
            val origin = if (method == "DESCRIBE" || method == "OPTIONS") upstreamOrigin else controlOrigin
            origin + suffix
        } else inboundTarget
        message.first = "$method $target $version"
        val digest = challenge
        val auth = credentials
        if (digest != null && auth?.size == 2 && message.get("Authorization")?.startsWith("Digest ", ignoreCase = true) == true) {
            RecorderRecordingDownload.digest(digest, Uri.decode(auth[0]), Uri.decode(auth[1]), method, target)
                ?.let { message.set("Authorization", it) }
        }
        if (method == "PLAY") {
            message.set("Scale", "1.0")
            message.set("Frames", "intra")
            message.set("Rate-Control", "no")
            message.get("CSeq")?.let { plays[it] = true }
            playSent = true
        }
    }

    private fun rewriteResponse(message: Message) {
        val status = message.first.split(' ', limit = 3).getOrNull(1)
        val auth = message.get("WWW-Authenticate")
        if (auth?.startsWith("Digest ", ignoreCase = true) == true) challenge = auth.drop(7)
        if (message.get("CSeq")?.let { plays.remove(it) } == true && status != "401") {
            playReply = if (status == "200") {
                val frames = message.get("Frames")?.take(24) ?: "unreported"
                val pacing = message.get("Rate-Control")?.take(8) ?: "unreported"
                "RTSP status 200, Frames $frames, Rate-Control $pacing"
            } else {
                "RTSP status ${status ?: "unknown"}"
            }
        }
        for (header in listOf("Content-Base", "Content-Location")) {
            val value = message.get(header) ?: continue
            if (value.startsWith("rtsp://", ignoreCase = true)) {
                val uri = Uri.parse(value)
                val authority = uri.encodedAuthority ?: continue
                controlOrigin = "rtsp://$authority"
                message.set(header, value.replaceFirst(controlOrigin, localOrigin))
            }
        }
        val info = message.get("RTP-Info")
        if (info != null) message.set("RTP-Info", urlOrigin.replace(info, localOrigin))
        if (message.get("Content-Type")?.startsWith("application/sdp", ignoreCase = true) == true) {
            message.body = urlOrigin.replace(message.body.toString(Charsets.UTF_8), localOrigin)
                .toByteArray(Charsets.UTF_8)
            message.set("Content-Length", message.body.size.toString())
        }
    }

    private fun relay(source: Socket, target: Socket, rewrite: (Message) -> Unit) {
        val input = BufferedInputStream(source.getInputStream())
        val output = BufferedOutputStream(target.getOutputStream())
        while (true) {
            val first = input.read()
            if (first < 0) return
            if (first == '$'.code) {
                val header = readBytes(input, 3)
                val size = ((header[1].toInt() and 255) shl 8) or (header[2].toInt() and 255)
                output.write(first)
                output.write(header)
                output.write(readBytes(input, size))
            } else {
                val start = readLine(input, first)
                val headers = mutableListOf<String>()
                while (true) {
                    val line = readLine(input)
                    if (line.isEmpty()) break
                    if (headers.size >= 128) throw IOException("Too many RTSP headers")
                    headers.add(line)
                }
                val message = Message(start, headers)
                val length = message.get("Content-Length")?.toIntOrNull() ?: 0
                if (length !in 0..1_048_576) throw IOException("Invalid RTSP body length")
                message.body = readBytes(input, length)
                rewrite(message)
                output.write((message.first + "\r\n" + message.headers.joinToString("\r\n") +
                    "\r\n\r\n").toByteArray(Charsets.ISO_8859_1))
                output.write(message.body)
            }
            output.flush()
        }
    }

    private fun readLine(input: BufferedInputStream, first: Int = input.read()): String {
        val line = ByteArrayOutputStream()
        var next = first
        while (next != '\n'.code) {
            if (next < 0) throw EOFException()
            if (line.size() >= 16_384) throw IOException("RTSP line too long")
            line.write(next)
            next = input.read()
        }
        return String(line.toByteArray(), Charsets.ISO_8859_1).removeSuffix("\r")
    }

    private fun readBytes(input: BufferedInputStream, length: Int): ByteArray {
        val bytes = ByteArray(length)
        var offset = 0
        while (offset < bytes.size) {
            val count = input.read(bytes, offset, bytes.size - offset)
            if (count < 0) throw EOFException()
            offset += count
        }
        return bytes
    }

    private class Message(var first: String, val headers: MutableList<String>) {
        var body = byteArrayOf()
        fun get(name: String): String? = headers.firstOrNull {
            it.substringBefore(':').equals(name, ignoreCase = true)
        }?.substringAfter(':')?.trim()

        fun set(name: String, value: String) {
            headers.removeAll { it.substringBefore(':').equals(name, ignoreCase = true) }
            headers.add("$name: $value")
        }
    }

    override fun close() {
        runCatching { downstream.close() }
        runCatching { client?.close() }
        runCatching { upstream.close() }
    }

    private companion object {
        val urlOrigin = Regex("rtsp://[^/\\s;,]+", RegexOption.IGNORE_CASE)
    }
}
