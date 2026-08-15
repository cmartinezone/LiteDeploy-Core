#!/usr/bin/env bash
# Promote Runtime/Shared scripts and DeploymentShare catalogs into tests/WinPEEnv.
# Mirrors Sync-WinPETestEnv.ps1 for Linux agents / CI. Does not overwrite BootConfig fixtures.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/tests/WinPEEnv"
SHARE="$ENV/Share"
SCRIPTS="$SHARE/Engine/Scripts"
RUNTIME="$ROOT/components/Runtime"

if [[ ! -d "$RUNTIME" ]]; then
  echo "Repo root does not look like LiteDeploy-Core: $ROOT" >&2
  exit 1
fi

mkdir -p "$SCRIPTS" "$SHARE/WorkLogs" "$SHARE/Engine/Tools"

copy_script() {
  local src="$1"
  if [[ ! -f "$src" ]]; then
    echo "Skip missing: $src" >&2
    return 0
  fi
  cp -f "$src" "$SCRIPTS/"
}

copy_script "$RUNTIME/BootInitializer/LiteDeploy.BootInitilizer.ps1"
copy_script "$RUNTIME/DeploymentEngine/LiteDeploy.DeploymentEngine.ps1"
copy_script "$RUNTIME/PreCheck/LiteDeploy.PreCheck.ps1"
copy_script "$RUNTIME/SelectWorkflow/LiteDeploy.SelectWorkFlow.ps1"
copy_script "$RUNTIME/SelectWorkflow/LiteDeploy.SelecWorkflowDriverPicker.ps1"
copy_script "$RUNTIME/UiHost/LiteDeploy.UiHost.ps1"
copy_script "$RUNTIME/Progress/LiteDeploy.Progress.ps1"
copy_script "$RUNTIME/HostShell/LiteDeploy.HostShell.ps1"
copy_script "$RUNTIME/LogWriter/LiteDeploy.LogWriter.ps1"
copy_script "$ROOT/components/Shared/OemDriverPacks/LiteDeploy.OemDriverPackCatalog.ps1"

rm -rf "$SHARE/Content" "$SHARE/WorkFlows"
cp -a "$ROOT/DeploymentShare/Content" "$SHARE/Content"
cp -a "$ROOT/DeploymentShare/WorkFlows" "$SHARE/WorkFlows"

count="$(find "$SCRIPTS" -maxdepth 1 -name '*.ps1' | wc -l | tr -d ' ')"
echo " [WinPEEnv] Promoted $count scripts → $SCRIPTS"
echo " [WinPEEnv] Share root             : $SHARE"
echo " [WinPEEnv] On Windows, run Start-WinPETestEnv.ps1 (subst + STA)."
