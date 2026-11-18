package net.zvektra.zvektra;

import java.io.File;
import kotlin.jvm.functions.Function0;
import kotlin.jvm.functions.Function2;

final class DahuaNativeDownload {

    static String scan(String host, int port, String user, String password,
                       int camera, long start, long end, String timezone,
                       Function0<Boolean> cancelled,
                       Function2<Long, byte[], Boolean> consume) {
        return "Dahua native SDK is unavailable";
    }

    static final boolean AVAILABLE = false;

    static boolean save(String host, int port, String user, String password, int camera,
                        long start, long end, String timezone, File output,
                        Function0<Boolean> cancelled) {
        return false;
    }
}
