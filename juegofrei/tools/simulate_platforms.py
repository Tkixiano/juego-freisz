"""Local platform pose simulator. Standard library only; Ctrl+C stops sending."""
from __future__ import annotations

import argparse
import json
import math
import socket
import time


def packet(sequence: int, elapsed: float) -> dict:
    return {
        "version": 1,
        "sequence": sequence,
        "modules": [
            {"id": 1, "x": 0.26 + 0.09 * math.sin(elapsed * math.tau / 10),
             "y": 0.70 + 0.07 * math.sin(elapsed * math.tau / 12),
             "angle": 12 * math.sin(elapsed * math.tau / 14), "visible": True},
            {"id": 2, "x": 0.74 - 0.08 * math.sin(elapsed * math.tau / 11),
             "y": 0.65 + 0.07 * math.cos(elapsed * math.tau / 13),
             "angle": -14 * math.sin(elapsed * math.tau / 15), "visible": True},
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5005)
    parser.add_argument("--hz", type=float, default=30)
    parser.add_argument("--duration", type=float, default=0, help="Seconds; 0 means until Ctrl+C")
    parser.add_argument("--start-sequence", type=int, default=None)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or not 1 <= args.hz <= 240 or not math.isfinite(args.duration) or args.duration < 0:
        parser.error("Invalid port, frequency or duration")
    sequence = args.start_sequence if args.start_sequence is not None else time.monotonic_ns() // 1_000_000
    if not 0 <= sequence <= 9_007_199_254_740_991:
        parser.error("Sequence must be a nonnegative safe JSON integer")
    start = time.monotonic()
    deadline = start
    sent = 0
    print(f"UDP -> {args.host}:{args.port}, {args.hz:g} Hz. Godot: F2 -> EXTERNAL. Ctrl+C stops.", flush=True)
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as peer:
            while args.duration == 0 or time.monotonic() - start < args.duration:
                now = time.monotonic()
                peer.sendto(json.dumps(packet(sequence, now-start), allow_nan=False, separators=(",", ":")).encode("utf-8"), (args.host, args.port))
                sequence += 1
                sent += 1
                # Skip missed deadlines instead of bursting old frames after a stall.
                deadline = max(deadline + 1 / args.hz, time.monotonic())
                time.sleep(max(0, deadline - time.monotonic()))
    except KeyboardInterrupt:
        pass
    print(f"Stopped. Sent {sent} packets in {time.monotonic()-start:.2f}s.", flush=True)


if __name__ == "__main__":
    main()
