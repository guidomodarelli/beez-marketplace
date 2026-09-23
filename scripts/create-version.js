#!/usr/bin/env node

'use strict';

/**
 * Interactive plugin version bumper.
 *
 * Updates the `version` field in BOTH provider manifests of a plugin
 * (`.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`), keeping
 * them in sync, then commits only those two manifests and pushes the branch.
 *
 * Usage:
 *   npm run create-version            -> interactive plugin menu
 *   npm run create-version <plugin>   -> target a plugin directly by name
 *   npm run create-version -- --dry-run | -n   -> preview without writing, committing or pushing
 *   npm run create-version -- --bump <kind> | --set <version>   -> skip the version prompt
 *   npm run create-version -- --help | -h   -> show usage
 */

const childProcess = require('child_process');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const REPOSITORY_ROOT = path.join(__dirname, '..');
const PLUGINS_DIR = path.join(REPOSITORY_ROOT, 'plugins');
const CLAUDE_MANIFEST = path.join('.claude-plugin', 'plugin.json');
const CODEX_MANIFEST = path.join('.codex-plugin', 'plugin.json');
const REMOTE_NAME = 'origin';
const DEFAULT_BRANCHES = ['develop', 'master', 'main'];
const DRY_RUN_FLAGS = ['--dry-run', '-n'];
const HELP_FLAGS = ['--help', '-h'];
const BUMP_FLAG = '--bump';
const SET_FLAG = '--set';
const SUPPORTED_OPTIONS = [...DRY_RUN_FLAGS, ...HELP_FLAGS, BUMP_FLAG, SET_FLAG];
const DRY_RUN_BANNER_MESSAGE = '🧪 DRY RUN · nothing will be written, committed or pushed';
const DRY_RUN_COMPLETE_MESSAGE = '🧪 DRY RUN complete · run again without --dry-run to apply';
const SEMVER_PATTERN = /^\d+\.\d+\.\d+$/;
const VERSION_FIELD_PATTERN = /("version"\s*:\s*")([^"]+)(")/;

/** Bump kinds offered for semantic version increments. */
const BUMP_KINDS = {
  patch: 'patch',
  minor: 'minor',
  major: 'major',
};

const BOX_WIDTH = 64;
const ANSI_ESCAPE_PATTERN = /\u001b\[[0-9;]*m/g;
const ZERO_WIDTH_CODE_POINTS = new Set([0x200d, 0xfe0f]);
const ANSI_CODES = {
  bold: '1',
  dim: '2',
  red: '31',
  green: '32',
  yellow: '33',
  magenta: '35',
  cyan: '36',
  gray: '90',
  black: '30',
  yellowBackground: '43',
};

const isColorEnabled =
  !process.env.NO_COLOR && (Boolean(process.env.FORCE_COLOR) || Boolean(process.stdout.isTTY));

/**
 * Wraps text in an ANSI style when colors are enabled.
 *
 * @param {string} styleName Key of ANSI_CODES.
 * @param {string} text Text to style.
 * @returns {string} Styled text, or the original text when colors are disabled.
 */
function paint(styleName, text) {
  return isColorEnabled ? `\u001b[${ANSI_CODES[styleName]}m${text}\u001b[0m` : text;
}

/**
 * Approximates terminal cell width, counting emoji as two cells and ANSI codes as zero.
 *
 * @param {string} text Text to measure.
 * @returns {number} Visible width in terminal cells.
 */
function visibleWidth(text) {
  return [...text.replace(ANSI_ESCAPE_PATTERN, '')].reduce((width, character) => {
    const codePoint = character.codePointAt(0);
    if (ZERO_WIDTH_CODE_POINTS.has(codePoint)) {
      return width;
    }
    const isWideSymbol = codePoint >= 0x1f300 || (codePoint >= 0x2600 && codePoint <= 0x27bf);
    return width + (isWideSymbol ? 2 : 1);
  }, 0);
}

/**
 * Renders a left-bordered panel; omitting the right border keeps emoji alignment stable.
 *
 * @param {string} title Panel title shown on the top border.
 * @param {string[]} lines Panel body lines.
 * @param {string} [borderStyle='cyan'] Key of ANSI_CODES for the border.
 * @returns {string} Rendered panel.
 */
function renderPanel(title, lines, borderStyle = 'cyan') {
  const border = (text) => paint(borderStyle, text);
  const topRuleLength = Math.max(BOX_WIDTH - visibleWidth(title) - 4, 3);
  return [
    `${border('╭─')} ${paint('bold', title)} ${border('─'.repeat(topRuleLength))}`,
    ...lines.map((line) => `${border('│')}  ${line}`),
    border(`╰${'─'.repeat(BOX_WIDTH - 1)}`),
  ].join('\n');
}

/**
 * Renders a full-width, heavy-bordered banner with a highlighted body line.
 *
 * @param {string} message Banner message.
 * @returns {string} Rendered banner.
 */
function renderAlertBanner(message) {
  const innerWidth = BOX_WIDTH - 2;
  const bodyText = `  ${message}`;
  const paddedBody = `${bodyText}${' '.repeat(Math.max(innerWidth - visibleWidth(bodyText), 0))}`;
  const highlight = (text) => paint('yellowBackground', paint('black', paint('bold', text)));
  const border = (text) => paint('yellow', paint('bold', text));
  return [
    border(`┏${'━'.repeat(innerWidth)}┓`),
    `${border('┃')}${highlight(paddedBody)}${border('┃')}`,
    border(`┗${'━'.repeat(innerWidth)}┛`),
  ].join('\n');
}

/**
 * Formats a version transition such as `1.0.0 → 1.0.1`.
 *
 * @param {string} fromVersion Previous version.
 * @param {string} toVersion Next version.
 * @returns {string} Styled transition.
 */
function formatVersionTransition(fromVersion, toVersion) {
  return `${paint('dim', fromVersion)} ${paint('gray', '→')} ${paint('green', paint('bold', toVersion))}`;
}

/**
 * Formats a numbered menu option.
 *
 * @param {number} optionNumber Option number typed by the user.
 * @param {string} label Option label.
 * @returns {string} Styled option line.
 */
function formatMenuOption(optionNumber, label) {
  return `  ${paint('magenta', paint('bold', String(optionNumber).padStart(2)))}  ${label}`;
}

/**
 * Formats an interactive prompt query.
 *
 * @param {string} query Prompt text.
 * @returns {string} Styled prompt.
 */
function formatPrompt(query) {
  return `\n${paint('cyan', '❯')} ${paint('bold', query)} `;
}

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
 * Executes a Git command from repository root and returns stdout.
 *
 * @param {string[]} args Git command arguments.
 * @returns {string} Command stdout.
 */
function runGit(args) {
  try {
    return childProcess.execFileSync('git', args, {
      cwd: REPOSITORY_ROOT,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const stderr = error.stderr ? String(error.stderr).trim() : '';
    const detail = stderr || error.message;
    throw new Error(`Git command failed: ${detail}`, { cause: error });
  }
}

/**
 * Finds first supported remote base reference available in the repository.
 *
 * @returns {string} Remote base reference, or empty string when none exists.
 */
function getRemoteBaseReference() {
  const candidates = DEFAULT_BRANCHES.map((branchName) => `${REMOTE_NAME}/${branchName}`);

  for (const candidate of candidates) {
    try {
      runGit(['show-ref', '--verify', '--quiet', `refs/remotes/${candidate}`]);
      return candidate;
    } catch (error) {
      // Try next supported base reference.
    }
  }

  return '';
}

/**
 * Returns paths changed in the current branch and working tree, including untracked files.
 *
 * @returns {string[]} Changed repository-relative paths.
 */
function getChangedPaths() {
  const remoteBaseReference = getRemoteBaseReference();
  const committedPaths = remoteBaseReference
    ? runGit(['diff', '--name-only', `${remoteBaseReference}...HEAD`])
    : '';
  const trackedPaths = runGit(['diff', '--name-only', 'HEAD']);
  const untrackedPaths = runGit(['ls-files', '--others', '--exclude-standard']);

  return [
    ...new Set(`${committedPaths}\n${trackedPaths}\n${untrackedPaths}`.split('\n').filter(Boolean)),
  ];
}

/**
 * Detects plugin names changed under `plugins/`, ignoring other paths.
 *
 * @returns {string[]} Unique changed plugin names.
 */
function detectChangedPluginNames() {
  return [...new Set(
    getChangedPaths()
      .map((changedPath) => changedPath.split('/'))
      .filter(([rootDirectory, pluginName]) => rootDirectory === 'plugins' && pluginName)
      .map(([, pluginName]) => pluginName)
  )];
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
 * Builds the version bump commit subject.
 *
 * @param {string} pluginName Selected plugin name.
 * @param {string} currentVersion Previous plugin version.
 * @param {string} newVersion New plugin version.
 * @returns {string} Commit subject.
 */
function buildCommitSubject(pluginName, currentVersion, newVersion) {
  return (
    `Bump the version number from ${currentVersion} to ${newVersion} in both ` +
    `"plugin.json" files for the "${pluginName}" plugin`
  );
}

/**
 * Commits only the updated provider manifests, leaving any other staged or
 * unstaged working-tree changes untouched.
 *
 * @param {string} subject Commit subject.
 * @param {string[]} manifestPaths Absolute paths of the manifests to commit.
 * @returns {{ hash: string, subject: string }} Created commit metadata.
 */
function commitVersionBump(subject, manifestPaths) {
  const commitMessage = `${subject}\n\nCo-Authored-By: Claude Code <noreply@anthropic.com>`;
  const relativeManifestPaths = manifestPaths.map((manifestPath) =>
    path.relative(REPOSITORY_ROOT, manifestPath)
  );

  runGit(['commit', '--only', '-m', commitMessage, '--', ...relativeManifestPaths]);

  return {
    hash: runGit(['rev-parse', '--short', 'HEAD']).trim(),
    subject,
  };
}

/**
 * Checks whether the current branch already tracks an upstream branch.
 *
 * @returns {boolean} True when an upstream is configured.
 */
function hasUpstreamBranch() {
  try {
    runGit(['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}']);
    return true;
  } catch (error) {
    return false;
  }
}

/**
 * Plans the push for the current branch, setting upstream on first push. Default branches
 * get no push arguments so bumps always travel through a pull request.
 *
 * @returns {{ branchName: string, pushArguments: string[] | null }} Push plan.
 */
function planPush() {
  const branchName = runGit(['rev-parse', '--abbrev-ref', 'HEAD']).trim();

  if (DEFAULT_BRANCHES.includes(branchName)) {
    return { branchName, pushArguments: null };
  }

  return {
    branchName,
    pushArguments: hasUpstreamBranch() ? ['push'] : ['push', '-u', REMOTE_NAME, 'HEAD'],
  };
}

/**
 * Executes a push plan. Never force-pushes.
 *
 * @param {{ branchName: string, pushArguments: string[] }} pushPlan Plan from planPush.
 */
function pushVersionBump({ branchName, pushArguments }) {
  try {
    runGit(pushArguments);
  } catch (error) {
    throw new Error(
      `Version bump commit was created but "git ${pushArguments.join(' ')}" failed for branch ` +
        `"${branchName}". Resolve the issue and push manually. ${error.message}`,
      { cause: error }
    );
  }
}

/**
 * Splits `--flag=value` into its name and inline value.
 *
 * @param {string} cliArgument Raw CLI argument.
 * @returns {{ flagName: string, inlineValue: string | undefined }} Flag parts.
 */
function splitFlag(cliArgument) {
  const separatorIndex = cliArgument.indexOf('=');
  if (!cliArgument.startsWith('--') || separatorIndex === -1) {
    return { flagName: cliArgument, inlineValue: undefined };
  }
  return {
    flagName: cliArgument.slice(0, separatorIndex),
    inlineValue: cliArgument.slice(separatorIndex + 1),
  };
}

/**
 * Parses CLI arguments into a plugin name and supported flags.
 *
 * @param {string[]} cliArguments Arguments after the script path.
 * @returns {{
 *   pluginName: string | undefined,
 *   isDryRun: boolean,
 *   isHelp: boolean,
 *   bumpKind: string | undefined,
 *   exactVersion: string | undefined,
 * }} Parsed options.
 */
function parseCliArguments(cliArguments) {
  const options = {
    pluginName: undefined,
    isDryRun: false,
    isHelp: false,
    bumpKind: undefined,
    exactVersion: undefined,
  };

  for (let argumentIndex = 0; argumentIndex < cliArguments.length; argumentIndex++) {
    const cliArgument = cliArguments[argumentIndex];
    const { flagName, inlineValue } = splitFlag(cliArgument);
    const readFlagValue = () => {
      const flagValue = inlineValue ?? cliArguments[++argumentIndex];
      if (!flagValue || (inlineValue === undefined && flagValue.startsWith('-'))) {
        throw new Error(`Option "${flagName}" requires a value. Run with --help for usage.`);
      }
      return flagValue;
    };

    if (DRY_RUN_FLAGS.includes(flagName)) {
      options.isDryRun = true;
    } else if (HELP_FLAGS.includes(flagName)) {
      options.isHelp = true;
    } else if (flagName === BUMP_FLAG) {
      const bumpKind = readFlagValue();
      if (!Object.values(BUMP_KINDS).includes(bumpKind)) {
        throw new Error(
          `Invalid ${BUMP_FLAG} value "${bumpKind}". Expected one of: ${Object.values(BUMP_KINDS).join(', ')}`
        );
      }
      options.bumpKind = bumpKind;
    } else if (flagName === SET_FLAG) {
      const exactVersion = readFlagValue();
      if (!SEMVER_PATTERN.test(exactVersion)) {
        throw new Error(`Invalid ${SET_FLAG} value "${exactVersion}". Expected MAJOR.MINOR.PATCH.`);
      }
      options.exactVersion = exactVersion;
    } else if (cliArgument.startsWith('-')) {
      throw new Error(`Unknown option "${cliArgument}". Supported options: ${SUPPORTED_OPTIONS.join(', ')}`);
    } else if (options.pluginName) {
      throw new Error(
        `Unexpected argument "${cliArgument}": plugin "${options.pluginName}" was already provided.`
      );
    } else {
      options.pluginName = cliArgument;
    }
  }

  if (options.bumpKind && options.exactVersion) {
    throw new Error(`Options ${BUMP_FLAG} and ${SET_FLAG} cannot be used together.`);
  }

  return options;
}

/**
 * Renders CLI usage help.
 *
 * @returns {string} Rendered help.
 */
function renderHelp() {
  const command = (text) => paint('cyan', text);
  const flag = (text) => paint('magenta', paint('bold', text.padEnd(24)));
  const section = (text) => paint('bold', text);
  const examples = [
    ['npm run create-version', 'interactive'],
    [`npm run create-version -- groot-kit ${BUMP_FLAG} minor`, 'no prompts'],
    [`npm run create-version -- -n ${SET_FLAG} 2.0.0`, 'preview exact version'],
  ];
  const exampleColumnWidth = Math.max(...examples.map(([exampleCommand]) => exampleCommand.length));
  return renderPanel('🌱 create-version · help', [
    section('Usage'),
    `  ${command('npm run create-version -- [plugin] [options]')}`,
    '',
    section('Options'),
    `  ${flag('-n, --dry-run')}Preview without writing, committing or pushing`,
    `  ${flag(`${BUMP_FLAG} <kind>`)}Bump without prompting: ${Object.values(BUMP_KINDS).join(' | ')}`,
    `  ${flag(`${SET_FLAG} <version>`)}Set an exact MAJOR.MINOR.PATCH version`,
    `  ${flag('-h, --help')}Show this help`,
    '',
    section('Examples'),
    ...examples.map(
      ([exampleCommand, description]) =>
        `  ${command(exampleCommand.padEnd(exampleColumnWidth))}  ${paint('gray', description)}`
    ),
  ]);
}

/**
 * Resolves the new version from CLI flags, falling back to the interactive menu.
 *
 * @param {(query: string) => Promise<string>} ask Prompt function.
 * @param {string} currentVersion Current synced version.
 * @param {{ bumpKind: string | undefined, exactVersion: string | undefined }} versionOptions CLI version options.
 * @returns {Promise<string>} The validated new version.
 */
async function resolveRequestedVersion(ask, currentVersion, { bumpKind, exactVersion }) {
  if (exactVersion) {
    console.log(`\n🎯 Using ${SET_FLAG}: ${formatVersionTransition(currentVersion, exactVersion)}`);
    return exactVersion;
  }
  if (bumpKind) {
    const bumpedVersion = bumpVersion(currentVersion, bumpKind);
    console.log(
      `\n🎚️  Using ${BUMP_FLAG} ${paint('bold', bumpKind)}: ${formatVersionTransition(currentVersion, bumpedVersion)}`
    );
    return bumpedVersion;
  }
  return resolveNewVersion(ask, currentVersion);
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
 * @param {string[]} changedPluginNames Plugin names detected from working-tree changes.
 * @returns {Promise<object>} The selected plugin descriptor.
 */
async function resolvePlugin(ask, plugins, requestedName, changedPluginNames) {
  if (requestedName) {
    const match = plugins.find((plugin) => plugin.name === requestedName);
    if (!match) {
      const available = plugins.map((plugin) => plugin.name).join(', ');
      throw new Error(`Plugin "${requestedName}" not found. Available: ${available}`);
    }
    return match;
  }

  if (changedPluginNames.length === 1) {
    const [changedPluginName] = changedPluginNames;
    const match = plugins.find((plugin) => plugin.name === changedPluginName);
    if (!match) {
      throw new Error(
        `Plugin "${changedPluginName}" changed under plugins/ but does not expose both provider manifests.`
      );
    }
    console.log(`\n🔍 Detected changed plugin: ${paint('cyan', paint('bold', match.name))}`);
    return match;
  }

  if (changedPluginNames.length > 1) {
    console.log(`\n🔍 Detected changed plugins: ${paint('cyan', changedPluginNames.join(', '))}`);
  }

  const changedMarker = paint('yellow', '● changed');
  console.log(
    `\n${renderPanel(
      '🧩 Available plugins',
      plugins.map((plugin, index) =>
        formatMenuOption(
          index + 1,
          changedPluginNames.includes(plugin.name) ? `${plugin.name}  ${changedMarker}` : plugin.name
        )
      )
    )}`
  );

  const answer = await ask(formatPrompt('Select a plugin by number:'));
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
  const transitionColumnWidth = Math.max(
    ...Object.values(BUMP_KINDS).map((bumpKind) =>
      visibleWidth(formatVersionTransition(currentVersion, bumpVersion(currentVersion, bumpKind)))
    )
  );
  const bumpOption = (emoji, bumpKind, hint) => {
    const transition = formatVersionTransition(currentVersion, bumpVersion(currentVersion, bumpKind));
    const padding = ' '.repeat(transitionColumnWidth - visibleWidth(transition));
    return `${emoji} ${paint('bold', bumpKind.padEnd(8))}${transition}${padding}  ${paint('gray', hint)}`;
  };

  console.log(
    `\n${renderPanel('🎚️  How do you want to set the new version?', [
      formatMenuOption(1, bumpOption('🩹', BUMP_KINDS.patch, 'fixes')),
      formatMenuOption(2, bumpOption('✨', BUMP_KINDS.minor, 'new features')),
      formatMenuOption(3, bumpOption('💥', BUMP_KINDS.major, 'breaking changes')),
      formatMenuOption(4, `🎯 ${paint('bold', 'custom'.padEnd(8))}${paint('gray', 'type an exact version')}`),
    ])}`
  );

  const choice = await ask(formatPrompt('Select an option [1-4]:'));

  switch (choice) {
    case '1':
      return bumpVersion(currentVersion, BUMP_KINDS.patch);
    case '2':
      return bumpVersion(currentVersion, BUMP_KINDS.minor);
    case '3':
      return bumpVersion(currentVersion, BUMP_KINDS.major);
    case '4': {
      const custom = await ask(formatPrompt('Enter the exact version (MAJOR.MINOR.PATCH):'));
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
  const cliOptions = parseCliArguments(process.argv.slice(2));
  const { pluginName: requestedName, isDryRun } = cliOptions;

  if (cliOptions.isHelp) {
    console.log(`\n${renderHelp()}\n`);
    return;
  }

  const plugins = discoverPlugins();
  const changedPluginNames = detectChangedPluginNames();

  if (plugins.length === 0) {
    throw new Error('No plugins with both Claude and Codex manifests were found.');
  }

  console.log(
    `\n🌱 ${paint('green', paint('bold', 'create-version'))} ` +
      paint('gray', '· plugin version bumper for Claude + Codex')
  );
  if (isDryRun) {
    console.log(`\n${renderAlertBanner(DRY_RUN_BANNER_MESSAGE)}`);
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const ask = createPrompter(rl);

  try {
    const plugin = await resolvePlugin(ask, plugins, requestedName, changedPluginNames);

    const claude = readManifest(plugin.claudePath);
    const codex = readManifest(plugin.codexPath);

    if (claude.version !== codex.version) {
      throw new Error(
        `Version mismatch in "${plugin.name}": ` +
          `Claude is ${claude.version} but Codex is ${codex.version}. ` +
          'Sync them manually before bumping.'
      );
    }

    const syncedBadge = paint('green', '✔ Claude · ✔ Codex in sync');
    console.log(
      `\n${renderPanel('📦 Plugin', [
        `${paint('gray', 'Name     ')} ${paint('cyan', paint('bold', plugin.name))}`,
        `${paint('gray', 'Version  ')} ${paint('bold', claude.version)}  ${syncedBadge}`,
      ])}`
    );

    const newVersion = await resolveRequestedVersion(ask, claude.version, cliOptions);

    if (newVersion === claude.version) {
      throw new Error(`New version "${newVersion}" matches the current version.`);
    }

    const subject = buildCommitSubject(plugin.name, claude.version, newVersion);
    const versionHeadline =
      `${paint('cyan', paint('bold', plugin.name))}  ${formatVersionTransition(claude.version, newVersion)}`;
    const manifestPaths = [plugin.claudePath, plugin.codexPath].map((manifestPath) =>
      paint('dim', path.relative(process.cwd(), manifestPath))
    );

    if (isDryRun) {
      const pushPlan = planPush();
      const pushLine = pushPlan.pushArguments
        ? `🚀 Would push "${paint('cyan', pushPlan.branchName)}" to ${REMOTE_NAME} ` +
          paint('gray', `(git ${pushPlan.pushArguments.join(' ')})`)
        : `⚠️  Would skip push: "${pushPlan.branchName}" is a default branch.`;

      console.log(
        `\n${renderPanel(
          '🧪 Dry run · no changes were made',
          [
            versionHeadline,
            '',
            ...manifestPaths.map((manifestPath) => `📝 Would update ${manifestPath}`),
            `🔖 Would commit only both manifests: ${subject}`,
            pushLine,
          ],
          'yellow'
        )}`
      );
      console.log(`\n${renderAlertBanner(DRY_RUN_COMPLETE_MESSAGE)}\n`);
      return;
    }

    writeManifestVersion(plugin.claudePath, claude.raw, newVersion);
    writeManifestVersion(plugin.codexPath, codex.raw, newVersion);

    const commit = commitVersionBump(subject, [plugin.claudePath, plugin.codexPath]);

    console.log(
      `\n${renderPanel(
        '✅ Version bumped',
        [
          versionHeadline,
          '',
          ...manifestPaths.map((manifestPath) => `📝 ${manifestPath}`),
          `🔖 Created commit ${paint('yellow', commit.hash)}: ${commit.subject}`,
        ],
        'green'
      )}`
    );

    const pushPlan = planPush();
    if (pushPlan.pushArguments) {
      pushVersionBump(pushPlan);
      console.log(`\n🚀 Pushed "${paint('cyan', pushPlan.branchName)}" to ${REMOTE_NAME}\n`);
    } else {
      console.log(
        `\n${paint('yellow', `⚠️  Skipped push: "${pushPlan.branchName}" is a default branch.`)} ` +
          'Push from a feature branch.\n'
      );
    }
  } finally {
    rl.close();
  }
}

main().catch((error) => {
  console.error(`\n${renderPanel('❌ create-version failed', [paint('red', error.message)], 'red')}\n`);
  process.exit(1);
});
