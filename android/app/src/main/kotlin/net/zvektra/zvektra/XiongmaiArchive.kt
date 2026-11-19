package net.zvektra.zvektra

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** DVRIP JPEG-file query only; never requests h264 files or OPMonitor/live snapshots. */
internal class XiongmaiArchive(private val host: String, private val port: Int,
    private val user: String, private val password: String, private val cancelled: () -> Boolean) {
    fun snapshots(camera: Int, start: Long, end: Long, timezone: String,
                  consume: (Long, ByteArray) -> Boolean) {
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone(timezone); isLenient = false
        }
        val seen = mutableSetOf<String>()
        Client().use { client ->
            client.login()
            var cursor = format.format(Date(start))
            while (!cancelled()) {
                client.send(1440, JSONObject().put("Name", "OPFileQuery").put("SessionID", client.session())
                    .put("OPFileQuery", JSONObject().put("BeginTime", cursor).put("EndTime", format.format(Date(end)))
                        .put("Channel", camera - 1).put("DriverTypeMask", "0x0000FFFF").put("Event", "*")
                        .put("StreamType", "0x00000000").put("Type", "jpg")))
                val response = client.json()
                if (response.optInt("Ret") != 100) throw IOException("DVRIP stored-JPEG query rejected (code ${response.optInt("Ret")}); archive support must be checked")
                val page = response.optJSONArray("OPFileQuery")
                    ?: throw IOException("DVRIP snapshot query returned no file-list field")
                var nextCursor = cursor
                var added = 0
                for (i in 0 until page.length()) {
                    if (cancelled()) return
                    val item = page.getJSONObject(i)
                    val name = item.optString("FileName")
                    if (!name.lowercase(Locale.US).endsWith(".jpg") && !name.lowercase(Locale.US).endsWith(".jpeg"))
                        throw IOException("Recorder ignored the JPG filter; no video was downloaded")
                    val begin = item.getString("BeginTime")
                    val timestamp = format.parse(begin)?.time ?: throw IOException("Invalid stored snapshot time")
                    nextCursor = maxOf(nextCursor, begin)
                    if (!seen.add(name)) continue
                    added++
                    if (seen.size > 10000) throw IOException("Snapshot result limit reached; choose a shorter range")
                    if (timestamp < start || timestamp >= end) continue
                    val jpeg = download(item)
                    if (!consume(timestamp, jpeg)) return
                }
                if (page.length() < 64) return
                if (added == 0 || nextCursor <= cursor) throw IOException("DVRIP snapshot pagination stopped advancing; results are incomplete")
                cursor = nextCursor
            }
        }
    }

    private fun download(item: JSONObject): ByteArray = Client().use { client ->
        client.login()
        val parameter = JSONObject().put("PlayMode", "ByName").put("FileName", item.getString("FileName"))
            .put("StreamType", 0).put("Value", 0).put("TransMode", "TCP")
        fun command(action: String) = JSONObject().put("Name", "OPPlayBack").put("SessionID", client.session())
            .put("OPPlayBack", JSONObject().put("Action", action).put("Parameter", parameter)
                .put("StartTime", item.getString("BeginTime")).put("EndTime", item.optString("EndTime", item.getString("BeginTime"))))
        client.send(1424, command("Claim"))
        if (client.json().optInt("Ret") != 100) throw IOException("Stored JPEG transfer is unsupported or denied")
        try {
            client.send(1420, command("DownloadStart"))
            val bytes = ByteArrayOutputStream()
            while (!cancelled()) {
                val chunk = client.packet()
                if (chunk.isEmpty()) break
                if (chunk[0] == '{'.code.toByte()) {
                    val json = JSONObject(chunk.toString(Charsets.UTF_8).trimEnd('\u0000', '\n', '\r'))
                    if (json.optInt("Ret") != 100) throw IOException("Stored JPEG transfer failed (code ${json.optInt("Ret")})")
                    continue
                }
                if (bytes.size() + chunk.size > 16 * 1024 * 1024) throw IOException("Stored JPEG exceeds size limit")
                bytes.write(chunk)
                val data = bytes.toByteArray()
                // Some devices wrap the JPEG in a native frame header. No video decoding occurs.
                val soi = (0 until data.size - 1).firstOrNull { data[it] == 0xff.toByte() && data[it + 1] == 0xd8.toByte() }
                if (soi != null) {
                    val eoi = (soi + 2 until data.size - 1).firstOrNull { data[it] == 0xff.toByte() && data[it + 1] == 0xd9.toByte() }
                    if (eoi != null) return@use data.copyOfRange(soi, eoi + 2)
                }
            }
            throw IOException("Stored JPEG transfer ended without a complete image")
        } finally { runCatching { client.send(1420, command("DownloadStop")) } }
    }

    private inner class Client : Closeable {
        private val socket = Socket().apply { connect(InetSocketAddress(host, port), 5000); soTimeout = 15000 }
        private var id = 0
        private var sequence = 0
        fun session() = "0x%08X".format(Locale.US, id)
        fun login() {
            val md5 = MessageDigest.getInstance("MD5").digest(password.toByteArray(Charsets.UTF_8))
            val alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
            val hash = (0 until 8).map { alphabet[((md5[it * 2].toInt() and 255) + (md5[it * 2 + 1].toInt() and 255)) % 62] }.joinToString("")
            send(1000, JSONObject().put("EncryptType", "MD5").put("LoginType", "DVRIP-Web")
                .put("PassWord", hash).put("UserName", user))
            val response = json()
            if (response.optInt("Ret") != 100) throw IOException("DVRIP login failed (code ${response.optInt("Ret")})")
            id = response.getString("SessionID").removePrefix("0x").toLong(16).toInt()
        }
        fun send(message: Int, value: JSONObject) {
            if (cancelled()) throw IOException("Stopped")
            val body = (value.toString() + "\n\u0000").toByteArray(Charsets.UTF_8)
            val header = ByteBuffer.allocate(20).order(ByteOrder.LITTLE_ENDIAN)
                .put(0xff.toByte()).put(0).putShort(0).putInt(id).putInt(sequence++).putShort(0)
                .putShort(message.toShort()).putInt(body.size).array()
            socket.getOutputStream().apply { write(header); write(body); flush() }
        }
        private fun exact(length: Int): ByteArray {
            val data = ByteArray(length)
            var offset = 0
            while (offset < length) {
                if (cancelled()) throw IOException("Stopped")
                val count = socket.getInputStream().read(data, offset, length - offset)
                if (count < 0) throw IOException("DVRIP archive connection closed")
                offset += count
            }
            return data
        }
        fun packet(): ByteArray {
            val header = exact(20)
            if (header[0] != 0xff.toByte()) throw IOException("Invalid DVRIP packet header")
            val length = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN).getInt(16)
            if (length !in 0..16 * 1024 * 1024) throw IOException("Invalid DVRIP packet length")
            return exact(length)
        }
        fun json() = JSONObject(packet().toString(Charsets.UTF_8).trimEnd('\u0000', '\n', '\r'))
        override fun close() { socket.close() }
    }
}
