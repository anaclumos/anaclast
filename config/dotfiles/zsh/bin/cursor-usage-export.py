#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlencode

DOWNLOAD_WAIT_S = 45
DEFAULT_DAYS = 30
INCOMPLETE_SUFFIXES = (".crdownload", ".download", ".part")
CHROME_BIN = Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
CHROME_USER_DATA = Path.home() / "Library/Application Support/Google/Chrome"
SKIP_PROFILE_DIRS = frozenset({"Guest Profile", "System Profile"})


def delete_path(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        return
    except PermissionError:
        print(f"warning: could not delete {path} (Downloads is TCC-locked)", file=sys.stderr)
    except OSError as exc:
        print(f"warning: could not delete {path}: {exc}", file=sys.stderr)


def applescript_posix(path: Path) -> str:
    return '"' + str(path.resolve()).replace("\\", "\\\\").replace('"', '\\"') + '"'


def copy_csv(src: Path, dest: Path) -> None:
    try:
        dest.write_bytes(src.read_bytes())
        return
    except PermissionError:
        pass
    script = f"""
set src to POSIX file {applescript_posix(src)}
set dest to POSIX file {applescript_posix(dest)}
set t to read src as «class utf8»
set fref to open for access dest with write permission
try
  set eof fref to 0
  write t to fref as «class utf8»
end try
close access dest
"""
    proc = subprocess.run(
        ["osascript"],
        capture_output=True,
        check=False,
        input=script,
        text=True,
        timeout=30,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "osascript failed").strip()
        raise RuntimeError(f"AppleScript copy failed: {err}")


def trailing_window_ms(days: int) -> tuple[int, int]:
    now = datetime.now(timezone.utc)
    today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    starting = today - timedelta(days=days - 1)
    ending = today + timedelta(days=1) - timedelta(milliseconds=1)
    return int(starting.timestamp() * 1000), int(ending.timestamp() * 1000)


def export_url(days: int) -> str:
    start_ms, end_ms = trailing_window_ms(days)
    query = urlencode(
        {
            "endDate": str(end_ms),
            "startDate": str(start_ms),
            "strategy": "tokens",
        }
    )
    return f"https://cursor.com/api/dashboard/export-usage-events-csv?{query}"


def profile_slug(profile_dir: str) -> str:
    return "".join(ch.lower() if ch.isalnum() else "-" for ch in profile_dir).strip("-")


def stable_path_for(profile_dir: str) -> Path:
    return Path(f"/tmp/cursor-usage-{profile_slug(profile_dir)}.csv")


def list_chrome_profiles() -> list[tuple[str, str]]:
    local_state = CHROME_USER_DATA / "Local State"
    try:
        payload = json.loads(local_state.read_text())
    except FileNotFoundError as exc:
        raise SystemExit(f"Chrome Local State missing at {local_state}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Chrome Local State is not JSON: {exc}") from exc
    cache = payload.get("profile", {}).get("info_cache", {})
    if not isinstance(cache, dict):
        raise SystemExit("Chrome Local State profile.info_cache is missing")
    rows: list[tuple[str, str]] = []
    for directory, meta in cache.items():
        if directory in SKIP_PROFILE_DIRS:
            continue
        if isinstance(meta, dict) and meta.get("is_ephemeral"):
            continue
        display = meta.get("name") if isinstance(meta, dict) else ""
        rows.append((directory, display if isinstance(display, str) else ""))
    rows.sort(key=lambda row: row[0])
    if not rows:
        raise SystemExit("no Chrome user profiles found in Local State")
    return rows


def resolve_profile(wanted: str) -> str:
    rows = list_chrome_profiles()
    for directory, display in rows:
        if wanted == directory or wanted == display:
            return directory
    known = ", ".join(f"{directory} ({display})" if display else directory for directory, display in rows)
    raise SystemExit(f"Chrome profile {wanted!r} is not a user profile (known: {known})")


def open_url_in_profile(url: str, profile_dir: str) -> None:
    if not CHROME_BIN.is_file():
        raise SystemExit(f"Google Chrome binary missing at {CHROME_BIN}")
    subprocess.Popen(
        [str(CHROME_BIN), f"--profile-directory={profile_dir}", url],
        start_new_session=True,
        stderr=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
    )


def known_usage_csv_names() -> list[str]:
    local_today = datetime.now().date()
    utc_today = datetime.now(timezone.utc).date()
    days = {local_today, utc_today, local_today - timedelta(days=1), utc_today - timedelta(days=1)}
    names: list[str] = []
    for day in days:
        iso = day.isoformat()
        for prefix in ("usage-events", "team-usage"):
            names.append(f"{prefix}-{iso}.csv")
            names.extend(f"{prefix}-{iso} ({n}).csv" for n in range(1, 16))
    return names


def newest_usage_csv(after_ts: float) -> Path | None:
    downloads = Path.home() / "Downloads"
    cands: list[tuple[float, Path]] = []

    def consider(path: Path) -> None:
        try:
            st = path.stat()
        except OSError:
            return
        if st.st_mtime < after_ts or path.name.endswith(".crdownload"):
            return
        cands.append((st.st_mtime, path))

    try:
        listed = list(downloads.glob("*.csv"))
    except OSError:
        listed = []
    for path in listed:
        name = path.name.lower()
        if "usage" in name or "team-usage" in name or "events" in name:
            consider(path)
    if not cands:
        for path in listed:
            consider(path)
    if not cands:
        for name in known_usage_csv_names():
            consider(downloads / name)
    if not cands:
        return None
    cands.sort(reverse=True)
    return cands[0][1]


def incomplete_sidecar_exists(path: Path) -> bool:
    return any(Path(str(path) + suffix).exists() for suffix in INCOMPLETE_SUFFIXES)


def looks_like_usage_csv(path: Path) -> bool:
    try:
        with path.open("rb") as handle:
            head = handle.read(256)
    except OSError:
        return False
    if head.startswith(b"\xef\xbb\xbf"):
        head = head[3:]
    return head.lstrip().startswith(b"Date")


def export_once(days: int, profile_dir: str) -> Path:
    dest = stable_path_for(profile_dir)
    url = export_url(days)
    after = time.time()
    print(f"opening {url} in Chrome profile {profile_dir}", file=sys.stderr)
    open_url_in_profile(url, profile_dir)
    deadline = after + DOWNLOAD_WAIT_S
    last_size: dict[str, int] = {}
    while time.time() < deadline:
        time.sleep(0.4)
        path = newest_usage_csv(after)
        if path is None or incomplete_sidecar_exists(path):
            continue
        try:
            size = path.stat().st_size
        except OSError:
            continue
        if size == 0:
            continue
        key = str(path)
        prev = last_size.get(key)
        last_size[key] = size
        if prev != size:
            continue
        try:
            copy_csv(path, dest)
        except (OSError, RuntimeError) as exc:
            print(f"warning: copy failed: {exc}", file=sys.stderr)
            continue
        if dest.stat().st_size == 0 or not looks_like_usage_csv(dest):
            continue
        if path.resolve() != dest.resolve():
            delete_path(path)
        print(dest.resolve())
        return dest
    raise RuntimeError(
        f"timed out waiting for usage CSV download in ~/Downloads "
        f"(is Chrome profile {profile_dir!r} logged into cursor.com on this host?)"
    )


def parse_days() -> int:
    raw = os.environ.get("CURSOR_USAGE_DAYS")
    if raw is None or raw.strip() == "":
        return DEFAULT_DAYS
    try:
        days = int(raw.strip())
    except ValueError as exc:
        raise SystemExit(
            f"CURSOR_USAGE_DAYS must be a positive integer (got {raw!r})"
        ) from exc
    if days <= 0:
        raise SystemExit(f"CURSOR_USAGE_DAYS must be a positive integer (got {days})")
    return days


def parse_profile() -> str:
    raw = (os.environ.get("CURSOR_USAGE_CHROME_PROFILE") or "").strip()
    if not raw:
        raise SystemExit("CURSOR_USAGE_CHROME_PROFILE is required (see --list-profiles)")
    return resolve_profile(raw)


def main() -> int:
    if "--list-profiles" in sys.argv[1:]:
        for directory, display in list_chrome_profiles():
            print(f"{directory}\t{display}")
        return 0
    days = parse_days()
    profile_dir = parse_profile()
    path = export_once(days, profile_dir)
    print(f"exported {path.name} ({path.stat().st_size} bytes)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
