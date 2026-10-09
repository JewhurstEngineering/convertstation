#!/usr/bin/env python3
"""Copy a local FFmpeg into the app bundle so the sandbox can launch it.

The binaries are not committed. Homebrew's GPL build is for this machine only.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")
# Bump when the copy set changes. The stamp is only the FFmpeg mtime, so a
# script-only change would otherwise skip the new libraries.
BUNDLE_REVISION = "2"
SDL3_CANDIDATES = (
    Path("/opt/homebrew/opt/sdl3/lib/libSDL3.dylib"),
    Path("/usr/local/opt/sdl3/lib/libSDL3.dylib"),
)


def run(command):
    subprocess.check_call(command)


def otool_lines(path):
    output = subprocess.check_output(["otool", "-L", str(path)], text=True)
    deps = []
    for line in output.splitlines()[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        deps.append(stripped.split(" (", 1)[0])
    return deps


def rpaths(path):
    output = subprocess.check_output(["otool", "-l", str(path)], text=True)
    found = []
    lines = output.splitlines()
    for index, line in enumerate(lines):
        if line.strip() != "cmd LC_RPATH":
            continue
        for follower in lines[index:index + 6]:
            text = follower.strip()
            if text.startswith("path "):
                found.append(text.split()[1])
                break
    return found


def is_system(dep):
    return dep.startswith(SYSTEM_PREFIXES)


def resolve_dep(dep, owner):
    owner = Path(owner)
    if dep.startswith("/"):
        return dep if os.path.exists(dep) else None
    name = None
    bases = []
    if dep.startswith("@rpath/"):
        name = dep[len("@rpath/"):]
        for raw in rpaths(owner):
            expanded = raw.replace("@loader_path", str(owner.parent)).replace("@executable_path", str(owner.parent))
            bases.append(Path(expanded))
    elif dep.startswith("@loader_path/"):
        name = dep[len("@loader_path/"):]
        bases.append(owner.parent)
    elif dep.startswith("@executable_path/"):
        name = dep[len("@executable_path/"):]
        bases.append(owner.parent)
    if name is None:
        return None
    for base in bases:
        candidate = (base / name).resolve()
        if candidate.exists():
            return str(candidate)
    return None


def find_tool(name):
    for candidate in (Path("/opt/homebrew/bin") / name, Path("/usr/local/bin") / name):
        if candidate.exists():
            return candidate.resolve()
    return None


def unique_dest(directory, real_path, used):
    name = Path(real_path).name
    dest = directory / name
    if dest not in used or used.get(dest) == real_path:
        return dest
    stem = Path(name).stem
    suffix = Path(name).suffix
    index = 2
    while True:
        dest = directory / f"{stem}-{index}{suffix}"
        if dest not in used:
            return dest
        index += 1


def main():
    if len(sys.argv) != 2:
        print("usage: bundle-ffmpeg.py ConvertStation.app", file=sys.stderr)
        return 1
    app = Path(sys.argv[1])
    if not app.exists():
        print(f"App bundle not found: {app}", file=sys.stderr)
        return 1

    ffmpeg = find_tool("ffmpeg")
    ffprobe = find_tool("ffprobe")
    if ffmpeg is None or ffprobe is None:
        print("warning: ffmpeg/ffprobe not found; the sandboxed app will have no engine")
        return 0

    helpers = app / "Contents" / "Helpers"
    frameworks = app / "Contents" / "Frameworks"
    helpers.mkdir(parents=True, exist_ok=True)
    frameworks.mkdir(parents=True, exist_ok=True)
    stamp = app.parent / ".ffmpeg-stamp"
    token = f"{BUNDLE_REVISION}:{ffmpeg}:{ffmpeg.stat().st_mtime}"
    if stamp.exists() and stamp.read_text() == token and (helpers / "ffmpeg").exists() and (helpers / "ffprobe").exists():
        sign(app, helpers, frameworks)
        return 0

    shutil.rmtree(helpers, ignore_errors=True)
    shutil.rmtree(frameworks, ignore_errors=True)
    helpers.mkdir(parents=True, exist_ok=True)
    frameworks.mkdir(parents=True, exist_ok=True)

    copied = {}
    items = []

    def add_library(original, dest_name=None):
        real = str(Path(original).resolve())
        if real in copied:
            return copied[real]
        if is_system(real):
            return None
        if dest_name:
            dest = frameworks / dest_name
        else:
            dest = unique_dest(frameworks, real, {value: key for key, value in copied.items()})
        shutil.copy2(real, dest)
        os.chmod(dest, 0o755)
        copied[real] = dest
        items.append((dest, Path(real), otool_lines(real), False))
        # Homebrew's "sdl2" is sdl2-compat. It is not linked to SDL3; it
        # dlopens @loader_path/libSDL3.dylib and, on failure, shows a modal
        # dialog that leaves a Dock icon up for every ffmpeg launch.
        if "sdl2-compat" in real:
            bundle_sdl3()
        return dest

    def bundle_sdl3():
        if bundle_sdl3.done:
            return
        bundle_sdl3.done = True
        for candidate in SDL3_CANDIDATES:
            if candidate.exists():
                add_library(candidate, dest_name="libSDL3.dylib")
                return
        print(
            "warning: sdl2-compat is bundled but libSDL3.dylib was not found; ffmpeg will show a fatal dialog",
            file=sys.stderr,
        )

    bundle_sdl3.done = False

    def add_executable(original, name):
        dest = helpers / name
        shutil.copy2(original, dest)
        os.chmod(dest, 0o755)
        items.append((dest, Path(original), otool_lines(original), True))

    add_executable(ffmpeg, "ffmpeg")
    add_executable(ffprobe, "ffprobe")

    index = 0
    while index < len(items):
        _, original, deps, is_exe = items[index]
        for dep in deps if is_exe else deps[1:]:
            if is_system(dep):
                continue
            resolved = resolve_dep(dep, original)
            if resolved is None:
                print(f"warning: could not resolve {dep} from {original}", file=sys.stderr)
                continue
            add_library(resolved)
        index += 1

    by_real = copied
    for dest, original, deps, is_exe in items:
        if not is_exe:
            run(["install_name_tool", "-id", f"@rpath/{dest.name}", str(dest)])
        for dep in (deps if is_exe else deps[1:]):
            if is_system(dep):
                continue
            resolved = resolve_dep(dep, original)
            if resolved is None:
                continue
            bundled = by_real.get(str(Path(resolved).resolve()))
            if bundled is None:
                continue
            run(["install_name_tool", "-change", dep, f"@rpath/{bundled.name}", str(dest)])
        rpath = "@executable_path/../Frameworks" if is_exe else "@loader_path"
        run(["install_name_tool", "-add_rpath", rpath, str(dest)])

    stamp.write_text(token)
    sign(app, helpers, frameworks)
    print(f"Bundled FFmpeg into {helpers} ({len(items) - 2} libraries)")
    return 0


def install_dock_icon(app):
    """The asset catalog icns only contains 16 and 128. Dock then draws the generic icon."""
    names = (
        "icon_16x16.png",
        "icon_16x16@2x.png",
        "icon_32x32.png",
        "icon_32x32@2x.png",
        "icon_128x128.png",
        "icon_128x128@2x.png",
        "icon_256x256.png",
        "icon_256x256@2x.png",
        "icon_512x512.png",
        "icon_512x512@2x.png",
    )
    source = Path(__file__).resolve().parents[1] / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    scratch = Path(tempfile.mkdtemp(prefix="cs-icon-"))
    iconset = scratch / "AppIcon.iconset"
    iconset.mkdir()
    copied = 0
    for name in names:
        src = source / name
        if not src.exists():
            continue
        shutil.copy2(src, iconset / name)
        copied += 1
    if copied < len(names):
        print("warning: app icon is missing sizes; the Dock icon may stay generic", file=sys.stderr)
        shutil.rmtree(scratch, ignore_errors=True)
        return
    dest = app / "Contents" / "Resources" / "AppIcon.icns"
    dest.parent.mkdir(parents=True, exist_ok=True)
    run(["iconutil", "-c", "icns", str(iconset), "-o", str(dest)])
    shutil.rmtree(scratch, ignore_errors=True)


def signing_identity():
    expanded = os.environ.get("EXPANDED_CODE_SIGN_IDENTITY", "").strip()
    named = os.environ.get("CODE_SIGN_IDENTITY", "").strip()
    identity = expanded or named or "-"
    if identity == "-":
        return "-", False
    hardened = (
        os.environ.get("ENABLE_HARDENED_RUNTIME", "") == "YES"
        or os.environ.get("CONFIGURATION") == "Release"
    )
    return identity, hardened


def codesign(path, identity, hardened, entitlements=None):
    command = ["codesign", "--force", "--sign", identity]
    if hardened and identity != "-":
        command.extend(["--options", "runtime", "--timestamp"])
    if entitlements is not None:
        command.extend(["--entitlements", str(entitlements)])
    command.append(str(path))
    run(command)


def sign(app, helpers, frameworks):
    install_dock_icon(app)
    root = Path(__file__).resolve().parents[1] / "ConvertStation"
    identity, hardened = signing_identity()
    helper_entitlements = root / "Helper.entitlements"
    if os.environ.get("CONFIGURATION") == "Release":
        app_entitlements = root / "ConvertStation-Release.entitlements"
    else:
        app_entitlements = root / "ConvertStation.entitlements"
    for library in frameworks.glob("*.dylib"):
        codesign(library, identity, hardened)
    for name in ("ffmpeg", "ffprobe"):
        tool = helpers / name
        if tool.exists():
            codesign(tool, identity, hardened, helper_entitlements)
    plugins = app / "Contents" / "PlugIns"
    if plugins.exists():
        for plugin in plugins.glob("*.xctest"):
            info = plugin / "Contents" / "Info.plist"
            binary = plugin / "Contents" / "MacOS" / plugin.stem
            if not info.exists() or not binary.exists():
                shutil.rmtree(plugin, ignore_errors=True)
                continue
            codesign(plugin, identity, hardened)
    for extra in (app / "Contents" / "MacOS").glob("*.dylib"):
        codesign(extra, identity, hardened)
    codesign(app, identity, hardened, app_entitlements)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print(error, file=sys.stderr)
        sys.exit(error.returncode or 1)
