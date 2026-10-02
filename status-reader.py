#!/usr/bin/env python3
"""status-reader: print the Magic Mouse battery status, or nothing.

BarWidget.qml runs this as a short-lived child process instead of reading
$XDG_RUNTIME_DIR/magic-mouse/battery.json itself. That file lives in a
directory other software could have tampered with, and a QML FileView would
open it from the shell's own event loop. Here a bad file can only ever cost this
child a moment:

  * the directory must be owned by this user and not writable by group/others;
  * the file is opened relative to that directory descriptor with O_NOFOLLOW
    and O_NONBLOCK, so a planted symlink is refused and a planted FIFO opens
    immediately instead of waiting for a writer;
  * fstat on the descriptor must say: regular file, owned by this user, not
    writable by group/others, at most MAX_BYTES long, and nothing is read
    before that has been checked;
  * the read is bounded by MAX_BYTES + 1 whatever fstat said (the file can grow);
  * the content must be one JSON object; it is re-serialised, so the shell only
    ever receives a small, well-formed document.

On any failure it prints nothing and exits 1 (2 for bad usage). A missing file is
the normal "daemon not running" case. Add -v to see why a file was refused.

usage: status-reader.py [-v] PATH
"""
import json
import os
import stat
import sys

MAX_BYTES = 4096


def refuse(why: str):
    raise ValueError(why)


def reject_constant(name: str):
    refuse(f"non-finite number {name}")


def read_status(path: str, max_bytes: int = MAX_BYTES) -> str:
    directory, name = os.path.split(path)
    if not directory or not name:
        refuse("need an absolute file path")
    uid = os.getuid()
    dfd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        dst = os.fstat(dfd)
        if dst.st_uid != uid:
            refuse(f"{directory} is not owned by this user")
        if dst.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            refuse(f"{directory} is writable by group or others")
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dfd)
    finally:
        os.close(dfd)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            refuse(f"{path} is not a regular file")
        if st.st_uid != uid:
            refuse(f"{path} is not owned by this user")
        if st.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
            refuse(f"{path} is writable by group or others")
        if st.st_size > max_bytes:
            refuse(f"{path} is larger than {max_bytes} bytes")
        data = b""
        while len(data) <= max_bytes:
            chunk = os.read(fd, max_bytes + 1 - len(data))
            if not chunk:
                break
            data += chunk
        if len(data) > max_bytes:
            refuse(f"{path} is larger than {max_bytes} bytes")
    finally:
        os.close(fd)
    doc = json.loads(data.decode("utf-8"), parse_constant=reject_constant)
    if not isinstance(doc, dict):
        refuse("status is not a JSON object")
    return json.dumps(doc, separators=(",", ":"))


def main(argv: list[str]) -> int:
    verbose = "-v" in argv
    args = [a for a in argv if a != "-v"]
    if len(args) != 1:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        out = read_status(args[0])
    except FileNotFoundError:
        return 1
    except (OSError, ValueError, RecursionError) as exc:  # Unicode and JSON decode errors are ValueErrors
        if verbose:
            print(f"status-reader: {exc}", file=sys.stderr)
        return 1
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
