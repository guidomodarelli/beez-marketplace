#!/usr/bin/env python3
"""Install pinned browser tools and add missing project MCP registrations."""

import argparse
import fcntl
import importlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile

try:
    import tomllib
except ImportError:
    print("Browser setup requires Python 3.11+; assets remain installed.", file=sys.stderr)
    sys.exit(1)

COMMAND_TIMEOUT_SECONDS = 600
SERVER_ALIASES = {
    "chrome-devtools": {"chrome-devtools", "chrome_devtools", "chrome-devtools-mcp"},
    "playwright": {"playwright", "playwright-mcp"},
    "agent-browser": {"agent-browser", "agent_browser"},
}


def ensure_safe_path(path):
    """Reject symlinked destinations and parents before filesystem writes."""
    for candidate in (path, *path.parents):
        if candidate.is_symlink():
            raise RuntimeError(f"Browser setup preserved symlinked path: {candidate}")


def read_config(path, parser, protect_destination=True):
    """Read existing user configuration without exposing its contents."""
    if not path.exists():
        return "", {}
    if protect_destination:
        ensure_safe_path(path)
    original = path.read_text()
    try:
        parsed = parser(original)
    except (ValueError, TypeError) as error:
        raise RuntimeError(f"Browser setup preserved malformed configuration: {path}") from error
    if not isinstance(parsed, dict):
        raise RuntimeError(f"Browser setup requires object configuration: {path}")
    return original, parsed


def atomic_write(path, content, original=None):
    """Replace a regular destination after checking the original snapshot."""
    ensure_safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if original is not None:
        current = path.read_text() if path.exists() else ""
        if current != original:
            raise RuntimeError(f"Browser setup preserved concurrent changes: {path}")
        if current == content:
            return
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as staged:
        staged.write(content)
        staged_path = Path(staged.name)
    try:
        os.chmod(staged_path, path.stat().st_mode & 0o777 if path.exists() else 0o600)
        ensure_safe_path(path)
        if original is not None and (path.read_text() if path.exists() else "") != original:
            raise RuntimeError(f"Browser setup preserved concurrent changes: {path}")
        os.replace(staged_path, path)
    finally:
        staged_path.unlink(missing_ok=True)


def run_command(arguments, operation, capture=False):
    """Run a bounded external operation without shell interpolation or raw logs."""
    print(f"Browser setup: {operation}", file=sys.stderr)
    with tempfile.NamedTemporaryFile(mode="w+", prefix="agent-ready-browser-", suffix=".log", delete=False) as diagnostic:
        log_path = Path(diagnostic.name)
        try:
            process = subprocess.Popen(
                arguments, stdout=subprocess.PIPE if capture else diagnostic,
                stderr=diagnostic, text=True, start_new_session=True,
            )
            stdout, _ = process.communicate(timeout=COMMAND_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired as error:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
            raise RuntimeError(f"Browser setup {operation} timed out; diagnostic: {log_path}; rerun bootstrap to resume") from error
        except OSError as error:
            log_path.unlink(missing_ok=True)
            raise RuntimeError(f"Browser setup could not start {operation}: {error.strerror}") from error
    if process.returncode:
        raise RuntimeError(f"Browser setup {operation} failed (exit {process.returncode}); diagnostic: {log_path}; rerun bootstrap to resume")
    log_path.unlink(missing_ok=True)
    return stdout.strip() if capture else ""


def install_tools(tools_root, versions):
    """Reuse pinned packages and download Chromium only when absent."""
    if not shutil.which("node") or not shutil.which("npm"):
        raise RuntimeError("Browser setup requires Node.js 24+ and npm; assets remain installed")
    node_version = run_command(["node", "--version"], "check Node.js", capture=True)
    if int(node_version.lstrip("v").split(".")[0]) < 24:
        raise RuntimeError("Browser setup requires Node.js 24+; Node.js was not upgraded")
    prefix = tools_root / "-".join(versions.values())
    ensure_safe_path(prefix)
    binaries = prefix / "node_modules/.bin"
    required_executables = ("chrome-devtools-mcp", "playwright-mcp", "agent-browser", "playwright")
    installed = True
    for package, version in versions.items():
        manifest = prefix / "node_modules" / package / "package.json"
        if not manifest.exists() or json.loads(manifest.read_text()).get("version") != version:
            installed = False
    installed = installed and all(os.access(binaries / name, os.X_OK) for name in required_executables)
    if not installed:
        run_command([
            "npm", "install", "--prefix", str(prefix), "--no-save", "--no-package-lock",
            "--no-audit", "--no-fund", *[f"{package}@{version}" for package, version in versions.items()],
        ], "install pinned browser packages")
    for executable in required_executables:
        if not os.access(binaries / executable, os.X_OK):
            raise RuntimeError(f"Browser setup missing installed executable: {executable}")
    browser_query = (
        "const {createRequire}=require('node:module');"
        "const load=createRequire(process.argv[1]);"
        "process.stdout.write(load('playwright').chromium.executablePath());"
    )
    browser = Path(run_command([
        "node", "-e", browser_query, str(prefix / "node_modules/@playwright/mcp/package.json"),
    ], "locate Chromium", capture=True))
    if not browser.is_file() or not os.access(browser, os.X_OK):
        run_command([str(binaries / "playwright"), "install", "chromium"], "download Chromium")
    if not browser.is_file() or not os.access(browser, os.X_OK):
        raise RuntimeError("Browser setup downloaded Chromium but executable remains unavailable")
    launch_probe = (
        "const {createRequire}=require('node:module');"
        "const load=createRequire(process.argv[1]);"
        "load('playwright').chromium.launch({headless:true,executablePath:process.argv[2]})"
        ".then(browser=>browser.close()).catch(error=>{console.error(error);process.exit(1)});"
    )
    run_command(["node", "-e", launch_probe, str(prefix / "node_modules/@playwright/mcp/package.json"), str(browser)],
                "verify headless Chromium launch")
    return binaries, browser


def load_toml_editor():
    """Reuse the TOML editor or install it in a private Python dependency directory."""
    try:
        return importlib.import_module("tomlkit")
    except ImportError:
        dependencies = Path.home() / ".local/share/agent-ready-setup/browser-tools/python"
        ensure_safe_path(dependencies)
        requirements = Path(__file__).with_name("requirements-browser.txt")
        dependencies.mkdir(parents=True, exist_ok=True)
        if not (dependencies / "tomlkit/__init__.py").is_file():
            run_command([sys.executable, "-m", "pip", "install", "--target", str(dependencies),
                         "--no-deps", "--requirement", str(requirements)], "install private TOML editor")
        sys.path.insert(0, str(dependencies))
        importlib.invalidate_caches()
        return importlib.import_module("tomlkit")


def register_servers(project, binaries, browser):
    """Add absent browser servers while preserving local and global overrides."""
    servers = {
        "chrome-devtools": {"command": str(binaries / "chrome-devtools-mcp"),
                            "args": ["--executablePath", str(browser), "--isolated", "--no-usage-statistics"]},
        "playwright": {"command": str(binaries / "playwright-mcp"),
                       "args": ["--executable-path", str(browser), "--isolated"]},
        "agent-browser": {"command": str(binaries / "agent-browser"),
                          "args": ["mcp"],
                          "env": {"AGENT_BROWSER_EXECUTABLE_PATH": str(browser)}},
    }
    if sys.platform.startswith("linux") and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        for name in ("chrome-devtools", "playwright"):
            servers[name]["args"].append("--headless")
    claude_config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    claude_global_path = Path(claude_config_dir) / ".claude.json" if claude_config_dir else Path.home() / ".claude.json"
    failures = []
    for provider, destination, global_path, parser, key in (
        ("Claude", project / ".mcp.json", claude_global_path, json.loads, "mcpServers"),
        ("Codex", project / ".codex/config.toml", Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))) / "config.toml", tomllib.loads, "mcp_servers"),
    ):
        try:
            original, config = read_config(destination, parser)
            _, global_config = read_config(global_path, parser, protect_destination=False)
            existing = config.get(key, {})
            global_servers = global_config.get(key, {})
            if not isinstance(existing, dict) or not isinstance(global_servers, dict):
                raise RuntimeError(f"Browser setup preserved invalid server map: {destination}")
            if provider == "Claude":
                projects = global_config.get("projects", {})
                if not isinstance(projects, dict):
                    raise RuntimeError(f"Browser setup preserved invalid project map: {global_path}")
                local_config = projects.get(str(project.resolve()), {})
                if not isinstance(local_config, dict) or not isinstance(local_config.get("mcpServers", {}), dict):
                    raise RuntimeError(f"Browser setup preserved invalid local server map: {global_path}")
                global_servers = {**global_servers, **local_config.get("mcpServers", {})}
            missing = {name: server for name, server in servers.items()
                       if not SERVER_ALIASES[name].intersection(set(existing) | set(global_servers))}
            if missing:
                if provider == "Claude":
                    config[key] = {**existing, **missing}
                    updated = json.dumps(config, indent=2) + "\n"
                else:
                    editor = load_toml_editor()
                    document = editor.parse(original)
                    if "mcp_servers" not in document:
                        document["mcp_servers"] = editor.table()
                    server_map = document["mcp_servers"]
                    for name, server in missing.items():
                        entry = editor.inline_table() if isinstance(server_map, editor.items.InlineTable) else editor.table()
                        entry.update(server)
                        server_map[name] = entry
                    updated = editor.dumps(document)
                    tomllib.loads(updated)
                atomic_write(destination, updated, original)
            print(f"Browser setup: {provider} registered {len(missing)} missing servers; existing definitions preserved", file=sys.stderr)
        except (OSError, RuntimeError, ValueError) as error:
            failures.append(str(error))
    if failures:
        raise RuntimeError("; ".join(failures))
    atomic_write(project / ".agents/browser-tools.json", json.dumps({
        "agent_browser": str(binaries / "agent-browser"), "browser_executable": str(browser),
    }, indent=2) + "\n")


def main():
    """Install once per pinned version and configure both supported providers."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--tools-root", type=Path, default=Path.home() / ".local/share/agent-ready-setup/browser-tools")
    arguments = parser.parse_args()
    arguments.project = arguments.project.absolute()
    arguments.tools_root = arguments.tools_root.absolute()
    versions = json.loads(Path(__file__).with_name("browser-tools.json").read_text())
    try:
        ensure_safe_path(arguments.project)
        ensure_safe_path(arguments.tools_root)
        arguments.tools_root.mkdir(parents=True, exist_ok=True)
        lock_path = arguments.tools_root / ".install.lock"
        ensure_safe_path(lock_path)
        with lock_path.open("w") as install_lock:
            try:
                fcntl.flock(install_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError("Browser setup already running; rerun bootstrap after it finishes") from error
            binaries, browser = install_tools(arguments.tools_root, versions)
            register_servers(arguments.project, binaries, browser)
        print("Browser setup complete. Restart provider and trust project MCPs when required. cua remains host-provided.", file=sys.stderr)
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Browser setup incomplete: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
