package net.zvektra.zvektra;

import android.util.Log;
import com.company.NetSDK.EM_QUERY_RECORD_TYPE;
import com.company.NetSDK.EM_USEDEV_MODE;
import com.company.NetSDK.INetSDK;
import com.company.NetSDK.NET_DEVICEINFO_Ex;
import com.company.NetSDK.NET_TIME;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import com.company.NetSDK.NET_RECORDFILE_INFO;
import java.util.Calendar;
import java.util.TimeZone;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import kotlin.jvm.functions.Function0;

final class DahuaNativeDownload {


    static synchronized long[][] motion(String host, int port, String user, String password,
                                        int camera, long start, long end, String timezone,
                                        Function0<Boolean> cancelled) throws IOException {
        if (cancelled.invoke()) return new long[0][];
        if (!INetSDK.Init((login, ip, serverPort) -> {})) throw new IOException("SDK initialization failed");
        try {
            INetSDK.SetConnectTime(3000, 1);
            long login = INetSDK.LoginEx2(host, port, user, password, 0, null,
                    new NET_DEVICEINFO_Ex(), 0);
            if (login == 0) throw new IOException("Login failed, SDK error " + INetSDK.GetLastError());
            try {
                ArrayList<long[]> intervals = new ArrayList<>();
                for (long from = start; from < end && !cancelled.invoke(); from += 300000) {
                    long to = Math.min(end, from + 300000);
                    NET_RECORDFILE_INFO[] records = new NET_RECORDFILE_INFO[512];
                    for (int i = 0; i < records.length; i++) records[i] = new NET_RECORDFILE_INFO();
                    // This legacy JNI API writes the Integer value. Use an uncached instance.
                    @SuppressWarnings("removal")
                    Integer count = new Integer(0);
                    if (!INetSDK.QueryRecordFile(login, camera - 1,
                            EM_QUERY_RECORD_TYPE.EM_RECORD_TYPE_MOTION_DETECT,
                            time(from, timezone), time(to, timezone), null, records, count, 5000, false)) {
                        throw new IOException("Motion query failed, SDK error " + INetSDK.GetLastError());
                    }
                    if (count < 0 || count >= records.length) {
                        throw new IOException("Motion query exceeded result capacity");
                    }
                    for (int i = 0; i < count; i++) {
                        long left = Math.max(from, epoch(records[i].starttime, timezone));
                        long right = Math.min(to, epoch(records[i].endtime, timezone));
                        if (right > left) intervals.add(new long[]{left, right});
                    }
                }
                return intervals.toArray(new long[intervals.size()][]);
            } finally {
                INetSDK.Logout(login);
            }
        } finally {
            INetSDK.Cleanup();
        }
    }

    private static long epoch(NET_TIME time, String timezone) {
        Calendar calendar = Calendar.getInstance(TimeZone.getTimeZone(timezone));
        calendar.clear();
        calendar.set((int) time.dwYear, (int) time.dwMonth - 1, (int) time.dwDay,
                (int) time.dwHour, (int) time.dwMinute, (int) time.dwSecond);
        return calendar.getTimeInMillis();
    }

    static final boolean AVAILABLE = true;

    // NetSDK initialization and cleanup apply to the entire process.
    static synchronized boolean save(String host, int port, String user, String password,
                                     int camera, long start, long end, String timezone,
                                     File output, Function0<Boolean> cancelled)
            throws InterruptedException {
        if (cancelled.invoke() || !INetSDK.Init((login, ip, serverPort) -> {})) return false;
        try {
            INetSDK.SetConnectTime(3000, 1);
            long login = INetSDK.LoginEx2(host, port, user, password, 0, null,
                    new NET_DEVICEINFO_Ex(), 0);
            if (login == 0) return failed("Login");
            try {
                if (cancelled.invoke()) return false;
                if (!INetSDK.SetDeviceMode(login, EM_USEDEV_MODE.SDK_RECORD_STREAM_TYPE, 1)) {
                    return failed("Select main stream");
                }
                CountDownLatch completed = new CountDownLatch(1);
                AtomicBoolean succeeded = new AtomicBoolean();
                long handle = INetSDK.DownloadByTimeEx(login, camera - 1,
                        EM_QUERY_RECORD_TYPE.EM_RECORD_TYPE_ALL, time(start, timezone),
                        time(end, timezone), output.getAbsolutePath(),
                        (download, total, downloaded, index, record) -> {
                            if (downloaded == -1 || downloaded == -2) {
                                succeeded.set(downloaded == -1);
                                completed.countDown();
                            }
                        }, null, null);
                if (handle == 0) return failed("Start download");
                boolean finished = false;
                try {
                    while (!cancelled.invoke()) {
                        if (completed.await(200, TimeUnit.MILLISECONDS)) {
                            finished = true;
                            break;
                        }
                    }
                } finally {
                    INetSDK.StopDownload(handle);
                }
                return finished && succeeded.get() && output.length() > 0;
            } finally {
                INetSDK.Logout(login);
            }
        } finally {
            INetSDK.Cleanup();
        }
    }

    private static boolean failed(String stage) {
        Log.w("BackgroundAgent", "Dahua " + stage + " failed, SDK error " + INetSDK.GetLastError());
        return false;
    }

    private static NET_TIME time(long epochMs, String timezone) {
        Calendar calendar = Calendar.getInstance(TimeZone.getTimeZone(timezone));
        calendar.setTimeInMillis(epochMs);
        return new NET_TIME(calendar.get(Calendar.YEAR), calendar.get(Calendar.MONTH) + 1,
                calendar.get(Calendar.DAY_OF_MONTH), calendar.get(Calendar.HOUR_OF_DAY),
                calendar.get(Calendar.MINUTE), calendar.get(Calendar.SECOND));
    }
}
