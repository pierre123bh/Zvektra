package net.zvektra.zvektra;

import java.io.File;
import kotlin.jvm.functions.Function0;

final class DahuaNativeDownload {
    static final boolean AVAILABLE = false;

    static boolean save(String host, int port, String user, String password, int camera,
                        long start, long end, String timezone, File output,
                        Function0<Boolean> cancelled) {
        return false;
    }
}
