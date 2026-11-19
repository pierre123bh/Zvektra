package net.zvektra.zvektra;

import java.io.File;
import java.io.IOException;
import kotlin.jvm.functions.Function2;
import kotlin.jvm.functions.Function0;

final class DahuaNativeDownload {


    static long[][] motion(String host, int port, String user, String password,
                           int camera, long start, long end, String timezone,
                           Function0<Boolean> cancelled) throws IOException {
        throw new IOException("Dahua native SDK is unavailable");
    }

    static int snapshots(String host, int port, String user, String password, int camera,
            long start, long end, String timezone, File cache, Function0<Boolean> cancelled,
            Function2<Long, byte[], Boolean> consume) throws IOException {
        throw new IOException("Dahua snapshot SDK is unavailable");
    }

    static final boolean AVAILABLE = false;

    static boolean save(String host, int port, String user, String password, int camera,
                        long start, long end, String timezone, File output,
                        Function0<Boolean> cancelled) {
        return false;
    }
}
