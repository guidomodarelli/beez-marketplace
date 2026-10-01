"""Exercise browser installation recovery and real JSON/TOML registration."""

import importlib.util
import json
import os
from pathlib import Path
import tempfile
import sys
import tomllib
import unittest
from unittest.mock import patch

try:
    import tomlkit
except ImportError:
    print("Browser test dependencies missing; run npm run setup:browser-tests before testing.", file=sys.stderr)
    sys.exit(1)

HELPER_PATH = Path(__file__).resolve().parents[1] / "scripts/setup-browser-tools.py"
SPEC = importlib.util.spec_from_file_location("browser_setup", HELPER_PATH)
browser_setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(browser_setup)


class BrowserToolsTests(unittest.TestCase):
    """Verify observable configuration and installation outcomes."""

    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.root = Path(self.workspace.name).resolve()
        self.project = self.root / "project"
        self.project.mkdir()
        self.binaries = self.root / "tools/bin"
        self.browser = self.root / "chromium"
        self.environment = patch.dict(os.environ, {"HOME": str(self.root), "CODEX_HOME": str(self.root / ".codex"), "CLAUDE_CONFIG_DIR": ""})
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.workspace.cleanup()

    def register(self):
        browser_setup.register_servers(self.project, self.binaries, self.browser)

    def test_should_register_all_three_servers_for_both_providers(self):
        self.register()
        claude = json.loads((self.project / ".mcp.json").read_text())["mcpServers"]
        codex = tomllib.loads((self.project / ".codex/config.toml").read_text())["mcp_servers"]
        self.assertEqual(claude, codex)
        self.assertEqual(set(claude), {"chrome-devtools", "playwright", "agent-browser"})
        self.assertEqual(claude["playwright"]["args"][:2], ["--executable-path", str(self.browser)])
        self.assertIn("--isolated", claude["playwright"]["args"])
        self.assertEqual(claude["agent-browser"]["env"], {"AGENT_BROWSER_EXECUTABLE_PATH": str(self.browser)})
        status = json.loads((self.project / ".agents/browser-tools.json").read_text())
        self.assertEqual(status["agent_browser"], str(self.binaries / "agent-browser"))

    def test_should_preserve_user_configuration_and_be_idempotent(self):
        (self.project / ".mcp.json").write_text(json.dumps({"custom": True, "mcpServers": {"playwright": {"command": "custom-browser"}}}))
        (self.project / ".codex").mkdir()
        (self.project / ".codex/config.toml").write_text('# custom comment\nmodel = "custom-model"\n[mcp_servers.playwright]\ncommand = "custom-browser"\nenabled = false\n')
        self.register()
        original_claude = (self.project / ".mcp.json").read_bytes()
        original_codex = (self.project / ".codex/config.toml").read_bytes()
        self.register()
        self.assertEqual((self.project / ".mcp.json").read_bytes(), original_claude)
        self.assertEqual((self.project / ".codex/config.toml").read_bytes(), original_codex)
        claude = json.loads(original_claude)
        codex = tomllib.loads(original_codex.decode())
        self.assertTrue(claude["custom"])
        self.assertEqual(claude["mcpServers"]["playwright"]["command"], "custom-browser")
        self.assertFalse(codex["mcp_servers"]["playwright"]["enabled"])
        self.assertEqual(codex["model"], "custom-model")

    def test_should_not_duplicate_global_aliases_even_when_global_config_is_symlinked(self):
        (self.root / ".claude.json").write_text(json.dumps({"mcpServers": {"chrome_devtools": {"command": "existing"}}}))
        (self.root / ".codex").mkdir()
        source = self.root / "global.toml"
        source.write_text('[mcp_servers.chrome_devtools]\ncommand = "existing"\n')
        (self.root / ".codex/config.toml").symlink_to(source)
        self.register()
        claude = json.loads((self.project / ".mcp.json").read_text())["mcpServers"]
        codex = tomllib.loads((self.project / ".codex/config.toml").read_text())["mcp_servers"]
        self.assertNotIn("chrome-devtools", claude)
        self.assertNotIn("chrome-devtools", codex)
        self.assertEqual(source.read_text(), '[mcp_servers.chrome_devtools]\ncommand = "existing"\n')

    def test_should_preserve_malformed_config_and_complete_other_provider(self):
        destination = self.project / ".mcp.json"
        destination.write_text("{malformed")
        with self.assertRaisesRegex(RuntimeError, "malformed configuration"):
            self.register()
        self.assertEqual(destination.read_text(), "{malformed")
        self.assertEqual(len(tomllib.loads((self.project / ".codex/config.toml").read_text())["mcp_servers"]), 3)

    def test_should_preserve_inline_codex_map_and_other_settings(self):
        (self.project / ".codex").mkdir()
        destination = self.project / ".codex/config.toml"
        destination.write_text('# custom settings\nmodel = "custom-model"\nmcp_servers = { custom = { command = "existing", enabled = false } } # preserved\n')
        self.register()
        result = tomllib.loads(destination.read_text())
        self.assertEqual(result["model"], "custom-model")
        self.assertEqual(result["mcp_servers"]["custom"], {"command": "existing", "enabled": False})
        self.assertEqual(set(result["mcp_servers"]), {"custom", "chrome-devtools", "playwright", "agent-browser"})
        first_write = destination.read_bytes()
        self.register()
        self.assertEqual(destination.read_bytes(), first_write)

    def test_should_not_duplicate_claude_local_scope_aliases(self):
        local = {"projects": {str(self.project): {"mcpServers": {"chrome_devtools": {"command": "existing"}}}}}
        (self.root / ".claude.json").write_text(json.dumps(local))
        self.register()
        servers = json.loads((self.project / ".mcp.json").read_text())["mcpServers"]
        self.assertNotIn("chrome-devtools", servers)
        self.assertEqual(json.loads((self.root / ".claude.json").read_text()), local)

    def test_should_preserve_servers_in_custom_claude_config_directory(self):
        directory = self.root / "custom-claude"
        directory.mkdir()
        configuration = {"mcpServers": {"chrome_devtools": {"command": "existing"}}}
        destination = directory / ".claude.json"
        destination.write_text(json.dumps(configuration))
        with patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": str(directory)}):
            self.register()
        servers = json.loads((self.project / ".mcp.json").read_text())["mcpServers"]
        self.assertNotIn("chrome-devtools", servers)
        self.assertEqual(json.loads(destination.read_text()), configuration)

    def test_should_use_headless_servers_on_linux_without_display(self):
        with patch.object(browser_setup.sys, "platform", "linux"), patch.dict(os.environ, {"DISPLAY": "", "WAYLAND_DISPLAY": ""}):
            self.register()
        servers = json.loads((self.project / ".mcp.json").read_text())["mcpServers"]
        self.assertIn("--headless", servers["chrome-devtools"]["args"])
        self.assertIn("--headless", servers["playwright"]["args"])

    def test_should_preserve_symlinked_config_without_touching_target(self):
        target = self.root / "target.json"
        target.write_text("{}")
        (self.project / ".mcp.json").symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "symlinked"):
            self.register()
        self.assertEqual(target.read_text(), "{}")
        self.assertTrue((self.project / ".mcp.json").is_symlink())

    def test_should_reject_stale_config_snapshot(self):
        destination = self.project / "config.json"
        destination.write_text("updated-by-user")
        with self.assertRaisesRegex(RuntimeError, "concurrent changes"):
            browser_setup.atomic_write(destination, "replacement", "old-snapshot")
        self.assertEqual(destination.read_text(), "updated-by-user")

    def test_should_reject_old_node_before_installing(self):
        # Mock only our external-command boundary to avoid changing host runtimes
        # or downloading packages. A separate real smoke test exercises npm/MCP.
        with patch.object(browser_setup, "run_command", return_value="v22.12.0") as commands:
            with self.assertRaisesRegex(RuntimeError, "Node.js 24"):
                browser_setup.install_tools(self.root / "tools", {"agent-browser": "0.38.0"})
        self.assertEqual(commands.call_count, 1)

    def test_should_skip_package_and_browser_downloads_when_already_installed(self):
        versions = json.loads(HELPER_PATH.with_name("browser-tools.json").read_text())
        prefix = self.root / "tools" / "-".join(versions.values())
        for package, version in versions.items():
            manifest = prefix / "node_modules" / package / "package.json"
            manifest.parent.mkdir(parents=True, exist_ok=True)
            manifest.write_text(json.dumps({"version": version}))
        binaries = prefix / "node_modules/.bin"
        binaries.mkdir()
        for name in ("chrome-devtools-mcp", "playwright-mcp", "agent-browser", "playwright"):
            (binaries / name).touch(mode=0o700)
        self.browser.touch(mode=0o700)
        with patch.object(browser_setup, "run_command", side_effect=["v24.17.0", str(self.browser), ""]) as commands:
            actual_binaries, actual_browser = browser_setup.install_tools(self.root / "tools", versions)
        self.assertEqual(actual_binaries, binaries)
        self.assertEqual(actual_browser, self.browser)
        self.assertEqual(commands.call_count, 3)

    def test_should_report_external_command_failure_with_private_diagnostic(self):
        with self.assertRaisesRegex(RuntimeError, "failed \\(exit 7\\); diagnostic:") as failure:
            browser_setup.run_command([sys.executable, "-c", "import sys; sys.exit(7)"], "install packages")
        diagnostic = Path(str(failure.exception).split("diagnostic: ")[1].split(";")[0])
        self.assertEqual(diagnostic.stat().st_mode & 0o777, 0o600)
        diagnostic.unlink()

    def test_should_repair_executables_missing_from_a_partial_installation(self):
        versions = json.loads(HELPER_PATH.with_name("browser-tools.json").read_text())
        prefix = self.root / "tools" / "-".join(versions.values())
        for package, version in versions.items():
            manifest = prefix / "node_modules" / package / "package.json"
            manifest.parent.mkdir(parents=True, exist_ok=True)
            manifest.write_text(json.dumps({"version": version}))
        self.browser.touch(mode=0o700)
        binaries = prefix / "node_modules/.bin"
        operations = []

        def external_operation(arguments, operation, capture=False):
            operations.append(arguments)
            if arguments[0] == "npm":
                binaries.mkdir()
                for name in ("chrome-devtools-mcp", "playwright-mcp", "agent-browser", "playwright"):
                    (binaries / name).touch(mode=0o700)
                return ""
            if arguments == ["node", "--version"]:
                return "v24.17.0"
            return str(self.browser) if capture else ""

        with patch.object(browser_setup, "run_command", side_effect=external_operation):
            actual_binaries, _ = browser_setup.install_tools(self.root / "tools", versions)
        self.assertEqual(actual_binaries, binaries)
        self.assertEqual(len([arguments for arguments in operations if arguments[0] == "npm"]), 1)
        self.assertTrue((binaries / "agent-browser").is_file())

    def test_should_stop_timed_out_command_and_allow_retry(self):
        with patch.object(browser_setup, "COMMAND_TIMEOUT_SECONDS", 0.05):
            with self.assertRaisesRegex(RuntimeError, "timed out") as failure:
                browser_setup.run_command([sys.executable, "-c", "import time; time.sleep(10)"], "download browser")
        diagnostic = Path(str(failure.exception).split("diagnostic: ")[1].split(";")[0])
        diagnostic.unlink()
        self.assertEqual(browser_setup.run_command([sys.executable, "-c", "print('ready')"], "retry", capture=True), "ready")

    @unittest.skipUnless(os.environ.get("AGENT_READY_SETUP_BROWSER_SMOKE_ROOT") and os.environ.get("AGENT_READY_SETUP_BROWSER_SMOKE_EXECUTABLE"),
                         "Set smoke root and executable to exercise installed Chromium without downloads")
    def test_should_launch_registered_chromium_when_cache_has_no_headless_shell(self):
        browser = Path(os.environ["AGENT_READY_SETUP_BROWSER_SMOKE_EXECUTABLE"])
        chromium_directory = next(parent for parent in browser.parents if parent.name.startswith("chromium-"))
        cache = self.root / "browser-cache"
        cache.mkdir()
        (cache / chromium_directory.name).symlink_to(chromium_directory, target_is_directory=True)
        versions = json.loads(HELPER_PATH.with_name("browser-tools.json").read_text())
        with patch.dict(os.environ, {"PLAYWRIGHT_BROWSERS_PATH": str(cache)}):
            _, executable = browser_setup.install_tools(Path(os.environ["AGENT_READY_SETUP_BROWSER_SMOKE_ROOT"]), versions)
        self.assertTrue(executable.is_file())
        self.assertTrue(executable.is_relative_to(cache))


if __name__ == "__main__":
    unittest.main()
