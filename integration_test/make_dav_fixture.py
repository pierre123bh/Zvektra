"""Wrap H.264 access units in Dahua DAV records for the Android smoke test."""
import json
import struct
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
packets = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_packets",
    "-show_entries", "packet=pos,size,flags", "-of", "json", source,
]))["packets"]
data = source.read_bytes()
start = datetime(2024, 11, 15, 15)
with destination.open("wb") as out:
    for index, packet in enumerate(packets):
        position, size = int(packet["pos"]), int(packet["size"])
        keyframe = "K" in packet["flags"]
        milliseconds = 100 * index
        timestamp = start + timedelta(milliseconds=milliseconds)
        date = ((timestamp.year - 2000) << 26 | timestamp.month << 22 |
                timestamp.day << 17 | timestamp.hour << 12 |
                timestamp.minute << 6 | timestamp.second)
        # 480x360, H.264, 10 frames/s. Only keyframes need stream metadata.
        extra = bytes((0x80, 0, 60, 45, 0x81, 0, 4, 10)) if keyframe else b""
        record_size = 24 + len(extra) + size + 8
        out.write(struct.pack(
            "<4sBBBBIIIHBB", b"DHAV", 0xFD if keyframe else 0xFC, 0, 0, 0,
            index, record_size, date, milliseconds & 0xFFFF, len(extra), 0,
        ))
        out.write(extra)
        out.write(data[position:position + size])
        out.write(struct.pack("<4sI", b"dhav", record_size))
