package net.zvektra.zvektra

import android.net.Uri
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

internal object DahuaRecordingDownload {
    fun save(source: Uri, port: Int, camera: Int, start: Long, duration: Long,
             timezone: String, file: File, cancelled: () -> Boolean): Boolean {
        val host = source.host ?: return false
        val userInfo = source.encodedUserInfo ?: return false
        val credentials = userInfo.split(':', limit = 2)
        if (credentials.size != 2) return false
        val username = Uri.decode(credentials[0])
        val password = Uri.decode(credentials[1])
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).apply {
            timeZone = TimeZone.getTimeZone(timezone)
        }
        val uri = Uri.Builder().scheme("http").encodedAuthority("$host:$port")
            .path("/cgi-bin/loadfile.cgi")
            .appendQueryParameter("action", "startLoad")
            .appendQueryParameter("channel", camera.toString())
            .appendQueryParameter("startTime", format.format(Date(start)))
            .appendQueryParameter("endTime", format.format(Date(start + duration)))
            .build()
        val url = URL(uri.toString())
        var authorization: String? = null
        for (attempt in 0..1) {
            if (cancelled()) return false
            val connection = url.openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 3500
                connection.readTimeout = 4000
                connection.instanceFollowRedirects = false
                connection.useCaches = false
                authorization?.let { connection.setRequestProperty("Authorization", it) }
                when (connection.responseCode) {
                    401 -> {
                        if (attempt != 0) return false
                        val challenge = connection.headerFields.entries
                            .filter { it.key.equals("WWW-Authenticate", ignoreCase = true) }
                            .flatMap { it.value }
                            .firstOrNull { it.startsWith("Digest ", ignoreCase = true) } ?: return false
                        authorization = digest(challenge.drop(7), username, password, url.file)
                            ?: return false
                    }
                    200 -> {
                        if (cancelled()) return false
                        val type = connection.contentType.orEmpty().lowercase(Locale.US)
                        if (type.startsWith("text/") || type.contains("json") || type.contains("xml")) return false
                        connection.inputStream.use { input ->
                            file.outputStream().buffered().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (!cancelled()) {
                                    val read = input.read(buffer)
                                    if (read == -1) {
                                        output.flush()
                                        return file.length() > 0
                                    }
                                    if (file.usableSpace < 64L * 1024 * 1024) return false
                                    output.write(buffer, 0, read)
                                }
                            }
                        }
                        return false
                    }
                    else -> return false
                }
            } finally {
                connection.disconnect()
            }
        }
        return false
    }

    private fun digest(challenge: String, user: String, password: String, path: String): String? {
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
        val ha2 = hash("GET:$path")
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
