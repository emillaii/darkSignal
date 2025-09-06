#!/usr/bin/env python3
import argparse
import io
import json
import os
import re
import sys
import time
from typing import Optional, Dict, Any, Iterable


ARROW_RE = re.compile(
    r"^Alert:\s+(?P<side>Buy|Sell)\s+Arrow\s+(?P<symbol>[A-Z0-9]+)\s+(?P<tf>[A-Z]\d+)\s+(?P<sig_time>\d{1,2}:\d{2})\s*$",
    re.IGNORECASE,
)

DARK_POINT_RE = re.compile(
    r"^Alert:\s+Dark Point\s+(?P<symbol>[A-Z0-9]+)\s+(?P<tf>[A-Z]\d+)\s+"
    r"(?P<sig_date>\d{4}\.\d{2}\.\d{2})\s+(?P<sig_time>\d{1,2}:\d{2})\s+"
    r"(?P<side>Buy|Sell)\s+Entry\s+at:\s+(?P<price>[0-9]+(?:\.[0-9]+)?)\s*$",
    re.IGNORECASE,
)

SRC_CTX_RE = re.compile(r"^(?P<src>.+?)\s*\((?P<symbol>[A-Z0-9]+),(?P<tf>[A-Z0-9]+)\)\s*$")


def parse_signal(fields: Iterable[str]) -> Optional[Dict[str, Any]]:
    """Parse a tab-separated log line into a signal dict, if applicable.

    Expected layout (tab-separated):
    - col0: short code (ignored)
    - col1: status (ignored)
    - col2: log time (e.g., 04:10:00.966)
    - col3: source context (e.g., "Dark Bands MT5 (BTCUSD,M5)")
    - col4: message (e.g., "Alert: Buy Arrow  XAUUSD M5 23:05")
    """
    cols = list(fields)
    if len(cols) < 5:
        return None

    _, _, log_time, src_ctx, message = cols[:5]

    # Extract helpful context from source column
    src_name = None
    src_symbol = None
    src_tf = None
    m = SRC_CTX_RE.match(src_ctx)
    if m:
        src_name = m.group("src").strip()
        src_symbol = m.group("symbol").upper()
        src_tf = m.group("tf").upper()

    # Try known message formats
    m = ARROW_RE.match(message)
    if m:
        side = m.group("side").lower()
        symbol = m.group("symbol").upper()
        tf = m.group("tf").upper()
        sig_time = m.group("sig_time")
        return {
            "type": "arrow",
            "side": side,
            "symbol": symbol,
            "timeframe": tf,
            "signal_time": sig_time,
            "log_time": log_time,
            "source": src_name or "",
        }

    m = DARK_POINT_RE.match(message)
    if m:
        side = m.group("side").lower()
        symbol = m.group("symbol").upper()
        tf = m.group("tf").upper()
        sig_date = m.group("sig_date")
        sig_time = m.group("sig_time")
        price = float(m.group("price"))
        # Convert date from YYYY.MM.DD to YYYY-MM-DD for ISO friendliness
        iso_date = sig_date.replace(".", "-")
        return {
            "type": "dark_point",
            "side": side,
            "symbol": symbol,
            "timeframe": tf,
            "signal_datetime": f"{iso_date} {sig_time}",
            "entry_price": price,
            "log_time": log_time,
            "source": src_name or "",
        }

    return None


def emit_json(obj: Dict[str, Any], out_fp: Optional[io.TextIOBase]):
    line = json.dumps(obj, ensure_ascii=False)
    print(line)
    sys.stdout.flush()
    if out_fp is not None:
        out_fp.write(line + "\n")
        out_fp.flush()


def follow_utf16(path: str, from_beginning: bool = False):
    """Generator yielding decoded lines as they are appended to a UTF-16 log.

    Handles basic truncation and rotation by watching inode and size.
    """
    last_stat = None
    text = None

    def open_text():
        raw = open(path, "rb")
        # Use UTF-16LE to avoid BOM requirement and allow mid-file reads
        return raw, io.TextIOWrapper(raw, encoding="utf-16-le")

    raw, text = open_text()
    try:
        if not from_beginning:
            # Fast-forward to end
            text.seek(0, os.SEEK_END)

        while True:
            # Read any available new lines
            line = text.readline()
            if line:
                yield line.rstrip("\r\n")
                continue

            # No new data; check for rotation/truncation
            try:
                st = os.stat(path)
            except FileNotFoundError:
                st = None

            # If file changed or truncated, reopen
            try:
                pos = text.tell()
            except Exception:
                pos = None

            if st is None or (last_stat and st.st_ino != last_stat.st_ino) or (
                last_stat and st.st_size < (pos or 0)
            ):
                try:
                    text.detach()
                except Exception:
                    pass
                try:
                    raw.close()
                except Exception:
                    pass
                time.sleep(0.2)
                raw, text = open_text()
                if not from_beginning:
                    text.seek(0, os.SEEK_END)
                last_stat = st
                continue

            last_stat = st
            time.sleep(0.2)
    finally:
        try:
            text.detach()
        except Exception:
            pass
        try:
            raw.close()
        except Exception:
            pass


def iter_file_once(path: str) -> Iterable[str]:
    with open(path, 'rb') as raw:
        text = io.TextIOWrapper(raw, encoding='utf-16-le')
        for line in text:
            yield line.rstrip('\r\n')


def main():
    ap = argparse.ArgumentParser(description="Monitor MT5 UTF-16 logs and extract Buy/Sell signals as JSON.")
    ap.add_argument("file", help="Path to the UTF-16 log file (e.g., 20250906.log)")
    ap.add_argument("--from-beginning", action="store_true", help="Process existing content before tailing")
    ap.add_argument("--out", default=None, help="Optional path to append JSON Lines (ndjson)")
    ap.add_argument("--symbols", default=None, help="Comma-separated symbol filter (e.g., BTCUSD,ETHUSD)")
    ap.add_argument("--once", action="store_true", help="Process existing content only and exit")
    args = ap.parse_args()

    sym_filter = None
    if args.symbols:
        sym_filter = {s.strip().upper() for s in args.symbols.split(',') if s.strip()}

    out_fp = open(args.out, "a", encoding="utf-8") if args.out else None
    try:
        line_iter: Iterable[str]
        if args.once:
            line_iter = iter_file_once(args.file)
        else:
            line_iter = follow_utf16(args.file, from_beginning=args.from_beginning)

        for raw_line in line_iter:
            # Split TSV fields
            parts = raw_line.split("\t")
            sig = parse_signal(parts)
            if not sig:
                continue
            if sym_filter and sig.get("symbol") not in sym_filter:
                continue
            emit_json(sig, out_fp)
    except KeyboardInterrupt:
        pass
    finally:
        if out_fp:
            out_fp.close()


if __name__ == "__main__":
    main()
