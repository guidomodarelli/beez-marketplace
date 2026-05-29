#!/usr/bin/env node

'use strict';

/**
 * Interactive plugin version bumper.
 *
 * Updates the `version` field in BOTH provider manifests of a plugin
 * (`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`), keeping
 * them in sync.
 *
 * Usage:
 *   npm run create-version            -> interactive plugin menu
 *   npm run create-version <plugin>   -> target a plugin directly by name
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const PLUGINS_DIR = path.join(__dirname, '..', 'plugins');
const CLAUDE_MANIFEST = path.join('.claude-plugin', 'plugin.json');
const CODEX_MANIFEST = path.join('.codex-plugin', 'plugin.json');
const SEMVER_PATTERN = /^\d+\.\d+\.\d+$/;
const VERSION_FIELD_PATTERN = /("version"\s*:\s*")([^"]+)(")/;

/** Bump kinds offered for semantic version increments. */
const BUMP_KINDS = {
  patch: 'patch',
  minor: 'minor',
  major: 'major',
};

/**
 * Reads the raw text and parsed `version` of a manifest file.
 *
 * @param {string} manifestPath Absolute path to a plugin.json file.
 * @returns {{ raw: string, version: string }} Raw file contents and its version.
 */
function readManifest(manifestPath) {
  const raw = fs.readFileSync(manifestPath, 'utf8');
  const parsed = JSON.parse(raw);
  if (typeof parsed.version !== 'string') {
    throw new Error(`Missing "version" field in ${manifestPath}`);
  }
  return { raw, version: parsed.version };
}

/**
 * Discovers plugins that expose both Claude and Codex manifests.
 *
 * @returns {Array<{ name: string, claudePath: string, codexPath: string }>} Discovered plugins.
 */
function discoverPlugins() {
  if (!fs.existsSync(PLUGINS_DIR)) {
    throw new Error(`Plugins directory not found: ${PLUGINS_DIR}`);
  }

  return fs
    .readdirSync(PLUGINS_DIR, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const pluginRoot = path.join(PLUGINS_DIR, entry.name);
      return {
        name: entry.name,
        claudePath: path.join(pluginRoot, CLAUDE_MANIFEST),
        codexPath: path.join(pluginRoot, CODEX_MANIFEST),
      };
    })
    .filter((plugin) => fs.existsSync(plugin.claudePath) && fs.existsSync(plugin.codexPath));
}

/**
 * Computes the next semantic version for the given bump kind.
 *
 * @param {string} currentVersion Current semver string (MAJOR.MINOR.PATCH).
 * @param {string} bumpKind One of BUMP_KINDS.
 * @returns {string} The next semver string.
 */
function bumpVersion(currentVersion, bumpKind) {
  const [major, minor, patch] = currentVersion.split('.').map(Number);
  switch (bumpKind) {
    case BUMP_KINDS.major:
      return `${major + 1}.0.0`;
    case BUMP_KINDS.minor:
      return `${major}.${minor + 1}.0`;
    case BUMP_KINDS.patch:
      return `${major}.${minor}.${patch + 1}`;
    default:
      throw new Error(`Unknown bump kind: ${bumpKind}`);
  }
}

/**
 * Rewrites only the `version` field of a manifest, preserving all other
 * formatting (indentation, key order, inline arrays) to keep diffs minimal.
 *
 * @param {string} manifestPath Absolute path to the manifest file.
 * @param {string} rawContents Current raw file contents.
 * @param {string} newVersion Version to write.
 */
function writeManifestVersion(manifestPath, rawContents, newVersion) {
  if (!VERSION_FIELD_PATTERN.test(rawContents)) {
    throw new Error(`Could not locate a "version" field to update in ${manifestPath}`);
  }
  const updated = rawContents.replace(VERSION_FIELD_PATTERN, `$1${newVersion}$3`);
  fs.writeFileSync(manifestPath, updated);
}

/**
 * Builds a promise-based prompt function over a readline interface.
 *
 * Uses a buffered `line` event queue instead of `rl.question` so that
 * multiple sequential prompts work reliably both on an interactive TTY and
 * with redirected stdin (where `rl.question` can drop later answers at EOF).
 *
 * @param {readline.Interface} rl Active readline interface.
 * @returns {(query: string) => Promise<string>} Prompt function returning the trimmed answer.
 */
function createPrompter(rl) {
  const pendingResolvers = [];
  const bufferedLines = [];
  let inputClosed = false;

  rl.on('line', (line) => {
    const resolve = pendingResolvers.shift();
    if (resolve) {
      resolve(line);
    } else {
      bufferedLines.push(line);
    }
  });

  rl.on('close', () => {
    inputClosed = true;
    while (pendingResolvers.length > 0) {
      pendingResolvers.shift()(null);
    }
  });

  return function ask(query) {
    process.stdout.write(query);
    return new Promise((resolve) => {
      if (bufferedLines.length > 0) {
        resolve(bufferedLines.shift());
      } else if (inputClosed) {
        resolve(null);
      } else {
        pendingResolvers.push(resolve);
      }
    }).then((line) => {
      if (line === null) {
        throw new Error('Input ended before an answer was provided.');
      }
      return line.trim();
    });
  };
}

/**
 * Resolves the target plugin from a CLI argument, falling back to an
 * interactive numbered menu.
 *
 * @param {(query: string) => Promise<string>} ask Prompt function.
 * @param {Array} plugins Discovered plugins.
 * @param {string|undefined} requestedName Plugin name passed via CLI.
 * @returns {Promise<object>} The selected plugin descriptor.
 */
async function resolvePlugin(ask, plugins, requestedName) {
  if (requestedName) {
    const match = plugins.find((plugin) => plugin.name === requestedName);
    if (!match) {
      const available = plugins.map((plugin) => plugin.name).join(', ');
      throw new Error(`Plugin "${requestedName}" not found. Available: ${available}`);
    }
    return match;
  }

  console.log('\nAvailable plugins:');
  plugins.forEach((plugin, index) => console.log(`  ${index + 1}) ${plugin.name}`));

  const answer = await ask('\nSelect a plugin by number: ');
  const selectedIndex = Number(answer) - 1;
  if (!Number.isInteger(selectedIndex) || selectedIndex < 0 || selectedIndex >= plugins.length) {
    throw new Error(`Invalid selection: "${answer}"`);
  }
  return plugins[selectedIndex];
}

/**
 * Prompts for the new version, offering semver bumps or a custom value.
 *
 * @param {(query: string) => Promise<string>} ask Prompt function.
 * @param {string} currentVersion Current synced version.
 * @returns {Promise<string>} The validated new version.
 */
async function resolveNewVersion(ask, currentVersion) {
  console.log('\nHow do you want to set the new version?');
  console.log(`  1) patch  -> ${bumpVersion(currentVersion, BUMP_KINDS.patch)}`);
  console.log(`  2) minor  -> ${bumpVersion(currentVersion, BUMP_KINDS.minor)}`);
  console.log(`  3) major  -> ${bumpVersion(currentVersion, BUMP_KINDS.major)}`);
  console.log('  4) custom -> type an exact version');

  const choice = await ask('\nSelect an option [1-4]: ');

  switch (choice) {
    case '1':
      return bumpVersion(currentVersion, BUMP_KINDS.patch);
    case '2':
      return bumpVersion(currentVersion, BUMP_KINDS.minor);
    case '3':
      return bumpVersion(currentVersion, BUMP_KINDS.major);
    case '4': {
      const custom = await ask('Enter the exact version (MAJOR.MINOR.PATCH): ');
      if (!SEMVER_PATTERN.test(custom)) {
        throw new Error(`Invalid semver version: "${custom}"`);
      }
      return custom;
    }
    default:
      throw new Error(`Invalid option: "${choice}"`);
  }
}

async function main() {
  const requestedName = process.argv[2];
  const plugins = discoverPlugins();

  if (plugins.length === 0) {
    throw new Error('No plugins with both Claude and Codex manifests were found.');
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = createPrompter(rl);

  try {
    const plugin = await resolvePlugin(ask, plugins, requestedName);

    const claude = readManifest(plugin.claudePath);
    const codex = readManifest(plugin.codexPath);

    if (claude.version !== codex.version) {
      throw new Error(
        `Version mismatch in "${plugin.name}": ` +
          `Claude is ${claude.version} but Codex is ${codex.version}. ` +
          'Sync them manually before bumping.'
      );
    }

    console.log(`\nPlugin: ${plugin.name}`);
    console.log(`Current version (synced): ${claude.version}`);

    const newVersion = await resolveNewVersion(ask, claude.version);

    if (newVersion === claude.version) {
      throw new Error(`New version "${newVersion}" matches the current version.`);
    }

    writeManifestVersion(plugin.claudePath, claude.raw, newVersion);
    writeManifestVersion(plugin.codexPath, codex.raw, newVersion);

    console.log(`\n✅ Updated "${plugin.name}" from ${claude.version} to ${newVersion}`);
    console.log(`   - ${path.relative(process.cwd(), plugin.claudePath)}`);
    console.log(`   - ${path.relative(process.cwd(), plugin.codexPath)}`);
  } finally {
    rl.close();
  }
}

main().catch((error) => {
  console.error(`\n❌ ${error.message}`);
  process.exit(1);
});
