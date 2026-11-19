package net.zvektra.zvektra

import org.w3c.dom.Element
import org.xml.sax.InputSource
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.StringReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID
import javax.xml.parsers.DocumentBuilderFactory

/** Authenticated stored-image APIs. Never calls live picture URLs or video searches. */
internal class StoredSnapshotHttp(host: String, port: Int, private val user: String,
    private val password: String, private val cancelled: () -> Boolean) {
    private val origin = "http://$host:$port"
    private fun escapeXml(value: String) = value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
    private fun encode(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
    fun search(family: String, camera: Int, start: Long, end: Long, timezone: String,
               consume: (Long, ByteArray) -> Boolean) {
        when (family) {
            "Dahua HTTP" -> dahua(camera, start, end, timezone, consume)
            "Hikvision" -> hikvision(camera, start, end, consume)
            else -> throw IOException("Snapshot archive HTTP API unavailable for $family")
        }
    }

    private fun dahua(camera: Int, start: Long, end: Long, timezone: String, consume: (Long, ByteArray) -> Boolean) {
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone(timezone); isLenient = false
        }
        val created = text("/cgi-bin/mediaFileFind.cgi?action=factory.create")
        val objectId = Regex("(?:^|\\n)object=(\\d+)").find(created)?.groupValues?.get(1)
            ?: throw IOException("Stored snapshot CGI search is unsupported or returned an invalid handle")
        fun command(action: String) = "/cgi-bin/mediaFileFind.cgi?action=$action&object=$objectId"
        try {
            val result = text(command("findFile") + "&condition.Channel=${camera - 1}" +
                "&condition.StartTime=${encode(format.format(Date(start)))}&condition.EndTime=${encode(format.format(Date(end)))}" +
                "&condition.Types%5B0%5D=jpg")
            if (result.trim() != "OK") throw IOException("Stored JPG search was rejected by the recorder")
            val seen = mutableSetOf<String>()
            while (!cancelled()) {
                val values = text(command("findNextFile") + "&count=50").lineSequence().mapNotNull {
                    val pair = it.trim().split('=', limit = 2)
                    if (pair.size == 2) pair[0] to pair[1] else null
                }.toMap()
                val count = values["found"]?.toIntOrNull() ?: throw IOException("Invalid stored-JPG search response")
                if (count !in 0..50) throw IOException("Invalid snapshot page size")
                for (index in 0 until count) {
                    if (cancelled()) return
                    val prefix = "items[$index]."
                    val path = values[prefix + "FilePath"] ?: throw IOException("Snapshot path missing")
                    if (!path.lowercase(Locale.US).endsWith(".jpg") && !path.lowercase(Locale.US).endsWith(".jpeg"))
                        throw IOException("Recorder returned a non-image file for the JPG search")
                    val timestamp = format.parse(values[prefix + "StartTime"] ?: "")?.time
                        ?: throw IOException("Stored snapshot time missing")
                    if (!seen.add(path)) throw IOException("Snapshot search repeated a page; results are incomplete")
                    if (seen.size > 10000) throw IOException("Snapshot limit reached; choose a shorter time range")
                    if (timestamp < start || timestamp >= end) continue
                    val escapedPath = path.split('/').joinToString("/") { encode(it) }
                    if (!consume(timestamp, request("/cgi-bin/RPC_Loadfile$escapedPath", null, 16 * 1024 * 1024, true))) return
                }
                if (count < 50) break
            }
        } finally {
            runCatching { text(command("close")) }
            runCatching { text(command("destroy")) }
        }
    }

    private fun hikvision(camera: Int, start: Long, end: Long, consume: (Long, ByteArray) -> Boolean) {
        val utc = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC"); isLenient = false }
        val id = UUID.randomUUID().toString()
        val seen = mutableSetOf<String>()
        var position = 0
        while (!cancelled()) {
            val body = """<CMSearchDescription version="2.0" xmlns="http://www.isapi.org/ver20/XMLSchema">
              <searchID>$id</searchID><trackIDList><trackID>${camera * 100 + 3}</trackID></trackIDList>
              <timeSpanList><timeSpan><startTime>${utc.format(Date(start))}</startTime><endTime>${utc.format(Date(end))}</endTime></timeSpan></timeSpanList>
              <maxResults>40</maxResults><searchResultPostion>$position</searchResultPostion>
            </CMSearchDescription>""".trimIndent()
            val text = text("/ISAPI/ContentMgmt/search", body)
            if (text.contains("<!DOCTYPE", true) || text.contains("<!ENTITY", true)) throw IOException("Invalid archive XML")
            val factory = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
            val xml = factory.newDocumentBuilder().parse(InputSource(StringReader(text)))
            fun elementText(element: Element, name: String) = element.getElementsByTagNameNS("*", name).item(0)?.textContent?.trim().orEmpty()
            val root = xml.documentElement
            val status = elementText(root, "responseStatus")
            val resultStatus = elementText(root, "responseStatusStrg").uppercase(Locale.US)
            if (status != "true" || resultStatus !in setOf("OK", "MORE", "NO MATCHES"))
                throw IOException("Stored-picture ISAPI search unsupported or rejected")
            val items = xml.getElementsByTagNameNS("*", "searchMatchItem")
            for (index in 0 until items.length) {
                if (cancelled()) return
                val item = items.item(index) as? Element ?: throw IOException("Invalid picture record")
                val content = elementText(item, "contentType").lowercase(Locale.US)
                val codec = elementText(item, "codecType").lowercase(Locale.US)
                if (content != "picture" && codec !in setOf("jpeg", "jpg")) throw IOException("Recorder returned video metadata for a picture-only query")
                val uri = elementText(item, "playbackURI")
                if (uri.isEmpty() || !seen.add(uri)) throw IOException("Missing or repeated stored snapshot URI")
                if (seen.size > 10000) throw IOException("Snapshot limit reached; choose a shorter range")
                val stamp = elementText(item, "startTime")
                val timestamp = parseTime(stamp) ?: throw IOException("Invalid stored snapshot time")
                if (timestamp < start || timestamp >= end) continue
                val download = "<downloadRequest version=\"1.0\" xmlns=\"http://www.isapi.org/ver20/XMLSchema\"><playbackURI>${escapeXml(uri)}</playbackURI></downloadRequest>"
                if (!consume(timestamp, request("/ISAPI/ContentMgmt/download", download, 16 * 1024 * 1024, true))) return
            }
            if (resultStatus != "MORE") return
            if (items.length == 0) throw IOException("Picture search reported more results without returning a page")
            position += items.length
        }
    }

    private fun parseTime(value: String): Long? {
        val normalized = value.replace(Regex("Z$"), "+0000").replace(Regex("([+-]\\d\\d):(\\d\\d)$"), "$1$2")
        for (pattern in listOf("yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ")) {
            val formatter = SimpleDateFormat(pattern, Locale.US).apply { isLenient = false }
            runCatching { formatter.parse(normalized)?.time }.getOrNull()?.let { return it }
        }
        return null
    }

    private fun text(path: String, body: String? = null) = request(path, body, 1024 * 1024, false).toString(Charsets.UTF_8)
    private fun request(path: String, body: String?, limit: Int, image: Boolean): ByteArray {
        if (!path.startsWith('/')) throw IOException("Invalid archive request")
        val url = URL(origin + path)
        val method = if (body == null) "GET" else "POST"
        var authorization: String? = null
        for (attempt in 0..1) {
            if (cancelled()) throw IOException("Stopped")
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5000; connection.readTimeout = 15000
                connection.instanceFollowRedirects = false; connection.useCaches = false
                connection.requestMethod = method
                authorization?.let { connection.setRequestProperty("Authorization", it) }
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/xml; charset=UTF-8")
                    connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                }
                if (connection.responseCode == 401 && attempt == 0) {
                    val challenge = connection.headerFields.entries.filter { it.key.equals("WWW-Authenticate", true) }
                        .flatMap { it.value }.firstOrNull { it.startsWith("Digest ", true) }
                        ?: throw IOException("Recorder requires an unsupported authentication method")
                    authorization = digest(challenge.drop(7), user, password, method, url.file)
                        ?: throw IOException("Unsupported Digest authentication algorithm")
                    continue
                }
                if (connection.responseCode != 200) throw IOException("Snapshot archive HTTP ${connection.responseCode}; check API port, login and support")
                val type = connection.contentType.orEmpty().lowercase(Locale.US)
                if (image && (type.startsWith("video/") || type.startsWith("text/") || type.contains("xml") || type.contains("json")))
                    throw IOException("Archive returned a non-image response; video was not downloaded")
                if (connection.contentLength > limit) throw IOException("Archive response exceeds size limit")
                val output = ByteArrayOutputStream()
                connection.inputStream.use { input ->
                    val buffer = ByteArray(16 * 1024)
                    while (!cancelled()) {
                        val count = input.read(buffer)
                        if (count < 0) return output.toByteArray()
                        if (output.size() + count > limit) throw IOException("Archive response exceeds size limit")
                        output.write(buffer, 0, count)
                    }
                    throw IOException("Stopped")
                }
            } finally { connection.disconnect() }
        }
        throw IOException("Recorder authentication failed")
    }
    private fun digest(challenge: String, user: String, password: String, method: String, path: String): String? {
        val fields = Regex("""([\w-]+)\s*=\s*(?:"([^"]*)"|([^,\s]+))""")
            .findAll(challenge).associate { match ->
                match.groupValues[1].lowercase(Locale.US) to
                    (match.groups[2]?.value ?: match.groupValues[3])
            }
        val realm = fields["realm"] ?: return null
        val nonce = fields["nonce"] ?: return null
        val algorithm = fields["algorithm"] ?: "MD5"
        val hashName = when (algorithm.uppercase(Locale.US)) {
            "MD5", "MD5-SESS" -> "MD5"
            "SHA-256", "SHA-256-SESS" -> "SHA-256"
            else -> return null
        }
        val qop = fields["qop"]
        if (qop != null && qop.split(',').none { it.trim().equals("auth", ignoreCase = true) }) return null
        fun hash(value: String) = MessageDigest.getInstance(hashName)
            .digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(Locale.US, it.toInt() and 255) }
        fun quoted(value: String) = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
        val cnonce = UUID.randomUUID().toString().replace("-", "")
        val initial = hash("$user:$realm:$password")
        val session = algorithm.endsWith("-sess", ignoreCase = true)
        val ha1 = if (session) hash("$initial:$nonce:$cnonce") else initial
        val ha2 = hash("$method:$path")
        val response = hash(if (qop == null) "$ha1:$nonce:$ha2"
            else "$ha1:$nonce:00000001:$cnonce:auth:$ha2")
        val values = mutableListOf(
            "username=" + quoted(user), "realm=" + quoted(realm), "nonce=" + quoted(nonce),
            "uri=" + quoted(path), "algorithm=$algorithm", "response=" + quoted(response),
        )
        fields["opaque"]?.let { values.add("opaque=" + quoted(it)) }
        if (qop != null) values.addAll(listOf("qop=auth", "nc=00000001"))
        if (qop != null || session) values.add("cnonce=" + quoted(cnonce))
        return "Digest " + values.joinToString(", ")
    }
}
