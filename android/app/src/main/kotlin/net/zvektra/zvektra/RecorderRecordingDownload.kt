package net.zvektra.zvektra

import android.net.Uri
import android.text.TextUtils
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

internal object RecorderRecordingDownload {
    fun save(source: Uri, port: Int, camera: Int, start: Long, duration: Long,
             timezone: String, family: String, file: File, cancelled: () -> Boolean): Boolean {
        val host = source.host ?: return false
        val credentials = source.encodedUserInfo?.split(':', limit = 2) ?: return false
        if (credentials.size != 2) return false
        val client = RecorderHttp("http://$host:$port", Uri.decode(credentials[0]),
            Uri.decode(credentials[1]), cancelled)
        if (family == "Hikvision") {
            return saveHikvision(client, camera, start, start + duration, file)
        }
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone(timezone)
        }
        val rangeStart = format.format(Date(start)).replace(" ", "%20")
        val rangeEnd = format.format(Date(start + duration)).replace(" ", "%20")
        val path = "/cgi-bin/loadfile.cgi?action=startLoad&channel=$camera" +
            "&startTime=$rangeStart&endTime=$rangeEnd&subtype=0"
        return client.save(path, file)
    }

    private fun saveHikvision(client: RecorderHttp, camera: Int, start: Long, end: Long, file: File): Boolean {
        val utc = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val from = utc.format(Date(start))
        val to = utc.format(Date(end))
        val search = """
            <CMSearchDescription xmlns="http://www.isapi.org/ver20/XMLSchema">
              <searchID>${UUID.randomUUID()}</searchID>
              <trackList><trackID>${camera * 100 + 1}</trackID></trackList>
              <timeSpanList><timeSpan><startTime>$from</startTime><endTime>$to</endTime></timeSpan></timeSpanList>
              <maxResults>2</maxResults><searchResultPostion>0</searchResultPostion>
            </CMSearchDescription>
        """.trimIndent()
        val playback = client.request("/ISAPI/ContentMgmt/search", search) { connection ->
            val parser = Xml.newPullParser().apply { setInput(connection.inputStream, null) }
            var matchedStart = ""
            var matchedEnd = ""
            var uri: String? = null
            while (parser.eventType != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG) {
                    when (parser.name) {
                        "searchMatchItem" -> { matchedStart = ""; matchedEnd = ""; uri = null }
                        "startTime" -> matchedStart = parser.nextText()
                        "endTime" -> matchedEnd = parser.nextText()
                        "playbackURI" -> uri = parser.nextText()
                    }
                }
                if (parser.eventType == XmlPullParser.END_TAG && parser.name == "searchMatchItem" &&
                    matchedStart == from && matchedEnd == to && uri?.startsWith("rtsp://") == true) {
                    return@request uri
                }
                parser.next()
            }
            null
        } ?: return false
        val xml = "<downloadRequest version=\"1.0\" xmlns=\"http://www.isapi.org/ver20/XMLSchema\">" +
            "<playbackURI>${TextUtils.htmlEncode(playback)}</playbackURI></downloadRequest>"
        return client.save("/ISAPI/ContentMgmt/download", file, xml)
    }

    private class RecorderHttp(
        private val origin: String,
        private val username: String,
        private val password: String,
        private val cancelled: () -> Boolean,
    ) {
        fun save(path: String, file: File, body: String? = null): Boolean =
            request(path, body) { connection ->
                val type = connection.contentType.orEmpty().lowercase(Locale.US)
                if (type.startsWith("text/") || type.contains("json") || type.contains("xml")) return@request false
                connection.inputStream.use { input ->
                    file.outputStream().buffered().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (!cancelled()) {
                            val read = input.read(buffer)
                            if (read == -1) {
                                output.flush()
                                return@request file.length() > 0
                            }
                            if (file.usableSpace < 64L * 1024 * 1024) return@request false
                            output.write(buffer, 0, read)
                        }
                    }
                }
                false
            } ?: false

        fun <T> request(path: String, body: String?, read: (HttpURLConnection) -> T?): T? {
            val url = URL(origin + path)
            val method = if (body == null) "GET" else "POST"
            var authorization: String? = null
            for (attempt in 0..1) {
                if (cancelled()) return null
                val connection = url.openConnection() as HttpURLConnection
                try {
                    connection.connectTimeout = 3500
                    connection.readTimeout = 4000
                    connection.instanceFollowRedirects = false
                    connection.useCaches = false
                    connection.requestMethod = method
                    authorization?.let { connection.setRequestProperty("Authorization", it) }
                    if (body != null) {
                        val bytes = body.toByteArray(Charsets.UTF_8)
                        connection.doOutput = true
                        connection.setRequestProperty("Content-Type", "application/xml; charset=UTF-8")
                        connection.setFixedLengthStreamingMode(bytes.size)
                        connection.outputStream.use { it.write(bytes) }
                    }
                    when (connection.responseCode) {
                        401 -> {
                            if (attempt != 0) return null
                            val challenge = connection.headerFields.entries
                                .filter { it.key.equals("WWW-Authenticate", ignoreCase = true) }
                                .flatMap { it.value }
                                .firstOrNull { it.startsWith("Digest ", ignoreCase = true) } ?: return null
                            authorization = digest(challenge.drop(7), username, password, method, url.file)
                                ?: return null
                        }
                        200 -> return if (cancelled()) null else read(connection)
                        else -> return null
                    }
                } finally {
                    connection.disconnect()
                }
            }
            return null
        }
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
