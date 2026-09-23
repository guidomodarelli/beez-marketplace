#!/usr/bin/env bash
# Reports the latest groot-ui version and configures frontend helper scripts.
# Package installation remains an explicit user action so package-lock.json is
# updated together with the user's chosen package.json version.

set -euo pipefail

readonly GROOT_UI_PACKAGE_NAME="groot-ui"
readonly I18N_SCRIPT_NAME="i18n"
readonly I18N_SCRIPT_COMMAND="groot-i18n"
readonly LOCAL_TO_PRODUCTION_SCRIPT_NAME="local2prod"
readonly LOCAL_TO_PRODUCTION_SCRIPT_COMMAND="groot-config-sync"
readonly OBSOLETE_SCRIPT_NAMES_JSON='["i18n:gettext","i18n:upload","generate-po.zip","upload-translations","clean-locales"]'
readonly OBSOLETE_DEPENDENCY_NAMES_JSON='["kraken-translations"]'

package_json="${1:-package.json}"

if [[ $# -gt 1 ]]; then
  printf 'ERROR: usage: %s [package.json path]\n' "$0" >&2
  exit 1
fi

if [[ ! -e "$package_json" ]]; then
  printf '[groot-ui] %s was not found; version lookup skipped.\n' "$package_json"
  exit 0
fi

if [[ -L "$package_json" ]]; then
  printf 'ERROR: %s is a symlink; package configuration was not changed.\n' "$package_json" >&2
  exit 1
fi

if [[ ! -f "$package_json" ]]; then
  printf 'ERROR: %s is not a regular file; package configuration was not changed.\n' "$package_json" >&2
  exit 1
fi

# Callers may prefetch the registry lookup concurrently with other network work;
# the value is validated below exactly like a direct npm response.
latest_version="${AGENT_READY_SETUP_GROOT_UI_LATEST_VERSION:-}"
if [[ -z "$latest_version" ]]; then
  if ! command -v npm >/dev/null 2>&1; then
    printf 'ERROR: npm is required to look up the latest %s version.\n' "$GROOT_UI_PACKAGE_NAME" >&2
    exit 1
  fi
  if ! latest_version="$(npm view "$GROOT_UI_PACKAGE_NAME" version | tr -d '\r\n')"; then
    printf 'ERROR: could not look up the latest %s version.\n' "$GROOT_UI_PACKAGE_NAME" >&2
    exit 1
  fi
fi

if [[ ! "$latest_version" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  printf 'ERROR: npm returned an invalid latest %s version: %s\n' \
    "$GROOT_UI_PACKAGE_NAME" "$latest_version" >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  printf 'ERROR: node is required to configure %s.\n' "$package_json" >&2
  exit 1
fi

current_version_metadata="$(node - "$package_json" "$GROOT_UI_PACKAGE_NAME" <<'NODE'
const fs = require('fs');
const path = require('path');

const [packagePath, packageName] = process.argv.slice(2);
const packageDirectory = path.dirname(path.resolve(packagePath));
const dependencySections = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies',
];

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return null;
  }
}

const installedPackage = readJson(
  path.join(packageDirectory, 'node_modules', packageName, 'package.json'),
);
if (installedPackage && typeof installedPackage.version === 'string') {
  process.stdout.write(`installed\t${installedPackage.version}`);
  process.exit(0);
}

const lockfile = readJson(path.join(packageDirectory, 'package-lock.json'));
const lockedPackage = lockfile?.packages?.[`node_modules/${packageName}`];
if (lockedPackage && typeof lockedPackage.version === 'string') {
  process.stdout.write(`lockfile\t${lockedPackage.version}`);
  process.exit(0);
}

const legacyLockedPackage = lockfile?.dependencies?.[packageName];
if (legacyLockedPackage && typeof legacyLockedPackage.version === 'string') {
  process.stdout.write(`lockfile\t${legacyLockedPackage.version}`);
  process.exit(0);
}

const packageJson = readJson(packagePath);
for (const dependencySection of dependencySections) {
  const declaredVersion = packageJson?.[dependencySection]?.[packageName];
  if (typeof declaredVersion === 'string') {
    process.stdout.write(`declared\t${declaredVersion}`);
    process.exit(0);
  }
}

process.stdout.write('missing\t');
NODE
)"
current_version_source="${current_version_metadata%%$'\t'*}"
current_version="${current_version_metadata#*$'\t'}"

removed_dependency_names="$(node - "$package_json" \
  "$I18N_SCRIPT_NAME" \
  "$I18N_SCRIPT_COMMAND" \
  "$LOCAL_TO_PRODUCTION_SCRIPT_NAME" \
  "$LOCAL_TO_PRODUCTION_SCRIPT_COMMAND" \
  "$OBSOLETE_SCRIPT_NAMES_JSON" \
  "$OBSOLETE_DEPENDENCY_NAMES_JSON" <<'NODE'
const fs = require('fs');
const path = require('path');

const [
  packagePath,
  i18nScriptName,
  i18nScriptCommand,
  localToProductionScriptName,
  localToProductionScriptCommand,
  obsoleteScriptNamesJson,
  obsoleteDependencyNamesJson,
] = process.argv.slice(2);
const obsoleteScriptNames = JSON.parse(obsoleteScriptNamesJson);
const obsoleteDependencyNames = JSON.parse(obsoleteDependencyNamesJson);
const dependencySections = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies',
];
let removedDependency = false;
let packageJson;

try {
  packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
} catch (error) {
  throw new Error(`could not parse ${packagePath}: ${error.message}`);
}

if (!packageJson || typeof packageJson !== 'object' || Array.isArray(packageJson)) {
  throw new Error(`${packagePath} must contain a JSON object`);
}

if (packageJson.scripts === undefined) {
  packageJson.scripts = {};
} else if (!packageJson.scripts || typeof packageJson.scripts !== 'object' || Array.isArray(packageJson.scripts)) {
  throw new Error(`${packagePath}.scripts must be a JSON object`);
}

for (const scriptName of obsoleteScriptNames) {
  delete packageJson.scripts[scriptName];
}
for (const dependencySection of dependencySections) {
  if (!packageJson[dependencySection] || typeof packageJson[dependencySection] !== 'object') {
    continue;
  }
  for (const dependencyName of obsoleteDependencyNames) {
    if (Object.prototype.hasOwnProperty.call(packageJson[dependencySection], dependencyName)) {
      delete packageJson[dependencySection][dependencyName];
      removedDependency = true;
    }
  }
}
packageJson.scripts[i18nScriptName] = i18nScriptCommand;
packageJson.scripts[localToProductionScriptName] = localToProductionScriptCommand;

const packageDirectory = path.dirname(packagePath);
const temporaryPackagePath = path.join(
  packageDirectory,
  `.${path.basename(packagePath)}.agent-ready-groot-ui-${process.pid}`,
);
const packageMode = fs.statSync(packagePath).mode & 0o777;

try {
  fs.writeFileSync(temporaryPackagePath, `${JSON.stringify(packageJson, null, 2)}\n`, { mode: packageMode });
  fs.chmodSync(temporaryPackagePath, packageMode);
  fs.renameSync(temporaryPackagePath, packagePath);
} catch (error) {
  fs.rmSync(temporaryPackagePath, { force: true });
  throw new Error(`could not update ${packagePath}: ${error.message}`);
}
process.stdout.write(removedDependency ? 'kraken-translations' : '');
NODE
)"

printf '[groot-ui] Latest available version: %s@%s\n' \
  "$GROOT_UI_PACKAGE_NAME" "$latest_version"
if [[ "$current_version" == "$latest_version" ]]; then
  printf '[groot-ui] Current effective version is %s (%s); no update is required.\n' \
    "$current_version" "$current_version_source"
else
  printf 'WARNING: [groot-ui] Current effective version is %s (%s); %s@%s is available.\n' \
    "${current_version:-not installed}" "$current_version_source" \
    "$GROOT_UI_PACKAGE_NAME" "$latest_version"
  printf '[groot-ui] To update manually, edit package.json and run: npm install --save %s@%s\n' \
    "$GROOT_UI_PACKAGE_NAME" "$latest_version"
fi
printf '[groot-ui] No package installation was performed.\n'
if [[ "$removed_dependency_names" == "kraken-translations" ]]; then
  printf '[groot-ui] kraken-translations was removed from package.json; run npm install to update package-lock.json.\n'
else
  printf '[groot-ui] kraken-translations was not declared in package.json; no npm install is required for its removal.\n'
fi
printf '[groot-ui] Configured %s and %s.\n' \
  "$I18N_SCRIPT_NAME" \
  "$LOCAL_TO_PRODUCTION_SCRIPT_NAME"
