import re
import sys
from pathlib import Path


def escape(message: str) -> str:
    return (
        message.replace("%", "%25")
        .replace("\r", "%0D")
        .replace("\n", "%0A")
    )


def emit(level: str, message: str, file_path: str | None = None, line: str | None = None, col: str | None = None, title: str | None = None) -> None:
    parts: list[str] = [f"::{level}"]
    metadata: list[str] = []
    if file_path:
        metadata.append(f"file={file_path}")
    if line:
        metadata.append(f"line={line}")
    if col:
        metadata.append(f"col={col}")
    if title:
        metadata.append(f"title={escape(title)}")
    if metadata:
        parts.append(" ")
        parts.append(",".join(metadata))
    parts.append("::")
    parts.append(escape(message))
    print("".join(parts))


def emit_log_tail(level: str, log_path: Path, title: str) -> None:
    lines = [
        line.rstrip()
        for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        if line.strip()
    ]
    if not lines:
        emit(level=level, title=title, message=f"{log_path.as_posix()} is empty")
        return

    tail = "\n".join(lines[-25:])
    emit(level=level, title=title, message=tail[-5000:])


def from_dart_machine(log_path: Path) -> int:
    count = 0
    for raw in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = raw.split("|", 7)
        if len(parts) != 8:
            continue
        severity, _type, code, file_path, line, col, _length, message = parts
        if severity not in {"ERROR", "WARNING"}:
            continue
        level = "error" if severity == "ERROR" else "warning"
        emit(
            level=level,
            file_path=Path(file_path).as_posix() if file_path else None,
            line=line or None,
            col=col or None,
            title=code or None,
            message=message.strip(),
        )
        count += 1
    return count


def from_flutter_build(log_path: Path) -> int:
    count = 0
    pattern = re.compile(
        r"^(?P<file>[^:\n]+\.dart):(?P<line>\d+):(?P<col>\d+): Error: (?P<message>.+)$"
    )
    for raw in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(raw.strip())
        if not match:
            continue
        emit(
            level="error",
            file_path=Path(match.group("file")).as_posix(),
            line=match.group("line"),
            col=match.group("col"),
            message=match.group("message"),
        )
        count += 1
    return count


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: emit_github_annotations.py <dart-machine|flutter-build> <log-path>", file=sys.stderr)
        return 2

    mode = sys.argv[1]
    log_path = Path(sys.argv[2])

    if mode == "dart-machine":
        count = from_dart_machine(log_path)
    elif mode == "flutter-build":
        count = from_flutter_build(log_path)
    else:
        print(f"unsupported mode: {mode}", file=sys.stderr)
        return 2

    if count == 0:
        emit(
            level="warning",
            message=f"No structured diagnostics were parsed from {log_path.as_posix()}",
        )
        emit_log_tail(
            level="warning",
            log_path=log_path,
            title="raw-log-tail",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
