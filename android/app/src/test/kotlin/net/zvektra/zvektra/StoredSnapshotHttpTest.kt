package net.zvektra.zvektra

import com.sun.net.httpserver.HttpServer
import org.junit.Assert.*
import org.junit.Test
import java.io.IOException
import java.net.InetSocketAddress
import java.util.Collections

class StoredSnapshotHttpTest {
    private fun server(block: (HttpServer, MutableList<String>) -> Unit) {
        val calls = Collections.synchronizedList(mutableListOf<String>())
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        try { block(server, calls) } finally { server.stop(0) }
    }
    @Test fun dahuaEmptySnapshotArchiveDoesNotRequestAnyImageOrVideo() = server { server, calls ->
        server.createContext("/") { exchange ->
            calls.add(exchange.requestURI.toString())
            val query = exchange.requestURI.query.orEmpty()
            val body = when {
                "factory.create" in query -> "object=77\n"
                "findNextFile" in query -> "found=0\n"
                else -> "OK\n"
            }.toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.start()
        StoredSnapshotHttp("127.0.0.1", server.address.port, "viewer", "fixture") { false }
            .search("Dahua HTTP", 2, 1763546400000, 1763546520000, "UTC") { _, _ -> fail("No images expected"); true }
        assertTrue(calls.any { it.contains("condition.Types%5B0%5D=jpg") })
        assertTrue(calls.any { it.contains("condition.Channel=1") })
        assertTrue(calls.any { it.contains("action=destroy") })
        assertFalse(calls.any { it.contains("loadfile", true) || it.contains("snapshot.cgi") || it.contains("dav") })
    }
    @Test fun unsupportedArchiveIsAnErrorNotAnEmptyResult() = server { server, _ ->
        server.createContext("/") { exchange -> exchange.sendResponseHeaders(404, -1); exchange.close() }
        server.start()
        try {
            StoredSnapshotHttp("127.0.0.1", server.address.port, "viewer", "fixture") { false }
                .search("Dahua HTTP", 1, 1, 2, "UTC") { _, _ -> true }
            fail("A missing API must not report no snapshots")
        } catch (expected: IOException) { assertTrue(expected.message!!.contains("404")) }
    }
    @Test fun hikvisionPictureSearchPagesAndPreservesActualImageTimestamp() = server { server, calls ->
        var page = 0
        val jpeg = byteArrayOf(0xff.toByte(), 0xd8.toByte(), 0xff.toByte(), 0xd9.toByte())
        server.createContext("/") { exchange ->
            val request = exchange.requestBody.bufferedReader().readText()
            calls.add(exchange.requestURI.path + ":" + request)
            val body: ByteArray
            if (exchange.requestURI.path.endsWith("/download")) {
                exchange.responseHeaders.add("Content-Type", "image/jpeg"); body = jpeg
            } else {
                page++
                val item = if (page == 1) """<searchMatchItem><trackID>203</trackID><timeSpan><startTime>2026-11-19T08:00:00Z</startTime></timeSpan><mediaSegmentDescriptor><contentType>picture</contentType><codecType>jpeg</codecType><playbackURI>http://192.168.1.55/image.jpg?name=a&amp;b=c</playbackURI></mediaSegmentDescriptor></searchMatchItem>""" else ""
                body = """<CMSearchResult><responseStatus>true</responseStatus><responseStatusStrg>${if (page == 1) "MORE" else "OK"}</responseStatusStrg><matchList>$item</matchList></CMSearchResult>""".toByteArray()
            }
            exchange.sendResponseHeaders(200, body.size.toLong()); exchange.responseBody.use { it.write(body) }
        }
        server.start()
        var count = 0
        val start = 1795075200000L // 2026-11-19 08:00 UTC
        StoredSnapshotHttp("127.0.0.1", server.address.port, "viewer", "fixture") { false }
            .search("Hikvision", 2, start, start + 120000, "UTC") { timestamp, data ->
                assertEquals(start, timestamp); assertArrayEquals(jpeg, data); count++; true
            }
        assertEquals(1, count)
        assertTrue(calls.any { it.contains("<trackID>203</trackID>") })
        assertTrue(calls.any { it.contains("<searchResultPostion>1</searchResultPostion>") })
        assertTrue(calls.filter { it.startsWith("/ISAPI/ContentMgmt/download") }.single().contains("&amp;b=c"))
    }
    @Test fun videoResultIsRejectedBeforeDownload() = server { server, calls ->
        server.createContext("/") { exchange ->
            calls.add(exchange.requestURI.path)
            val body = """<CMSearchResult><responseStatus>true</responseStatus><responseStatusStrg>OK</responseStatusStrg><matchList><searchMatchItem><contentType>video</contentType><codecType>H.264</codecType></searchMatchItem></matchList></CMSearchResult>""".toByteArray()
            exchange.sendResponseHeaders(200, body.size.toLong()); exchange.responseBody.use { it.write(body) }
        }
        server.start()
        try {
            StoredSnapshotHttp("127.0.0.1", server.address.port, "viewer", "fixture") { false }
                .search("Hikvision", 1, 1, 2, "UTC") { _, _ -> fail("Video is not a snapshot"); true }
            fail("Video metadata must be rejected")
        } catch (expected: IOException) { assertTrue(expected.message!!.contains("video")) }
        assertFalse(calls.any { it.endsWith("/download") })
    }
}
