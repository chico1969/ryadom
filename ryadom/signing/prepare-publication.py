"""Export reviewable source and a fork patch without changing the real Git index."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "dist/signpath-preparation"
BASE = json.loads((ROOT / "ryadom/upstream.lock.json").read_text("utf-8-sig"))["commit"]


def git(*args, env=None):
    return subprocess.check_output(["git", *args], cwd=ROOT, env=env)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    scratch = ROOT / ".tools/signpath"
    scratch.mkdir(parents=True, exist_ok=True)
    secrets = []
    for file in (ROOT / ".tools").glob("turn*.local.json"):
        for server in json.loads(file.read_text("utf-8-sig")):
            for key in ("username", "credential"):
                if server.get(key):
                    secrets.extend(server[key].encode(enc) for enc in ("utf-8", "utf-16-le"))
    for file in (ROOT / ".tools/alwaysdata").glob("id_ed25519*"):
        secrets.append(file.read_bytes().strip())
    fixture_name = "libs/hbb_common/tests/data/websocket-key.pem"
    hbb = ROOT / "libs/hbb_common"
    pinned_hbb = json.loads((ROOT / "ryadom/upstream.lock.json").read_text("utf-8-sig"))["submodules"]["libs/hbb_common"]
    public_fixture = subprocess.check_output(
        ["git", "-c", f"safe.directory={hbb.as_posix()}", "-C", str(hbb),
         "show", f"{pinned_hbb}:tests/data/websocket-key.pem"]
    )

    def safe(name, data):
        parts = Path(name).parts
        if any(part in (".tools", ".git", "node_modules", "build-logs") for part in parts):
            raise RuntimeError(f"Private/build path in export: {name}")
        if re.search(rb"(?m)^-----BEGIN (?:OPENSSH |RSA |EC |ENCRYPTED )?PRIVATE KEY-----\r?$", data):
            if name != fixture_name or data.replace(b"\r\n", b"\n") != public_fixture.replace(b"\r\n", b"\n"):
                raise RuntimeError(f"Private key marker in export: {name}")
        if any(secret and secret in data for secret in secrets):
            raise RuntimeError(f"Known owner credential in export: {name}")

    real_index = ROOT / ".git/index"
    index_before = real_index.read_bytes() if real_index.exists() else None
    # A separate index includes untracked application sources but obeys .gitignore.
    with tempfile.TemporaryDirectory(prefix="publication-", dir=scratch) as temp:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(temp) / "index"))
        git("read-tree", BASE, env=env)
        git("-c", "core.safecrlf=false", "-c", "core.autocrlf=false", "add", "--all", "--", ".", env=env)
        patch = git("diff", "--cached", "--binary", BASE, env=env)
        safe("Ryadom-from-upstream.patch", patch)
        (OUTPUT / "Ryadom-from-upstream.patch").write_bytes(patch)
        tracked = git("ls-files", "-z", env=env).decode("utf-8").split("\0")
        git("read-tree", BASE, env=env)
        git("apply", "--cached", "--check", "--whitespace=nowarn", str(OUTPUT / "Ryadom-from-upstream.patch"), env=env)
    if (real_index.read_bytes() if real_index.exists() else None) != index_before:
        raise RuntimeError("The real Git index changed unexpectedly")

    files = {name for name in tracked if name and (ROOT / name).is_file()}
    hbb_files = subprocess.check_output(
        ["git", "-c", f"safe.directory={hbb.as_posix()}", "-C", str(hbb), "ls-files", "-z"]
    ).decode("utf-8").split("\0")
    files.update(f"libs/hbb_common/{name}" for name in hbb_files if name and (hbb / name).is_file())
    files.update(f"libs/hbb_common/src/{name}.rs" for name in ("ryadom_dpapi", "ryadom_network"))
    # Include the corresponding generated bridge source in the source offer.
    generated = ("src/bridge_generated.rs", "src/bridge_generated.io.rs",
                 "flutter/lib/generated_bridge.dart", "flutter/lib/generated_bridge.freezed.dart",
                 "flutter/macos/Runner/bridge_generated.h", "flutter/ios/Runner/bridge_generated.h")
    files.update(name for name in generated if (ROOT / name).is_file())
    source_zip = OUTPUT / "Ryadom-Publication-Sources.zip"
    temporary_zip = source_zip.with_suffix(".zip.tmp")
    with zipfile.ZipFile(temporary_zip, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            data = (ROOT / name).read_bytes()
            safe(name, data)
            archive.writestr(name, data)
    temporary_zip.replace(source_zip)
    for name in ("CODE_SIGNING.md", "PRIVACY.md", "ryadom/signing/APPLICATION.md", "ryadom/signing/README_RU.md"):
        (OUTPUT / Path(name).name).write_bytes((ROOT / name).read_bytes())
    report = {
        "status": "prepared-not-submitted-not-signed",
        "owner": "chico1969", "proposedRepository": "https://github.com/chico1969/ryadom",
        "upstreamCommit": BASE, "sourceFiles": len(files), "realGitIndexUnchanged": True,
        "patchAppliesToPinnedUpstream": True,
        "publicTestKey": "Unchanged pinned upstream WebSocket test fixture; never an application credential",
        "knownOwnerCredentialsChecked": bool(secrets),
        "scope": "Known credentials/private-key markers and excluded paths only; not a full secret/license/security audit",
        "next": "Publish reviewed changes to the created public fork; maintainer MFA, CI and eligibility review must precede the application."
    }
    (OUTPUT / "PREPARATION.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    sums = []
    for file in sorted(OUTPUT.iterdir()):
        if file.is_file() and file.name != "SHA256SUMS.txt":
            sums.append(f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}")
    (OUTPUT / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
