#!/bin/bash
set -euo pipefail

# Installs plugin marketplaces into /usr/local/share/claude-defaults/plugins,
# replicating Claude Code's layout:
#   marketplaces/<marketplace>/                       full marketplace repo
#   cache/<marketplace>/<plugin>/<version>/           per-plugin cache
#   installed_plugins.json                            registry of installed plugins
#   known_marketplaces.json                           registry of known marketplaces
#
# Each entry under /plugins-src/<name>/ holds only pointer files:
#   .source-repo    GitHub <owner>/<repo>
#   .commit-sha     pinned commit SHA
#   .sparse-paths   (optional) space-separated paths for git sparse-checkout
#
# Sources are fetched from GitHub at the pinned SHA via partial+sparse clone.

SRC=/plugins-src
DEFAULTS=/usr/local/share/claude-defaults
PLUGINS=$DEFAULTS/plugins
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

mkdir -p "$PLUGINS/marketplaces" "$PLUGINS/cache"

installed_entries=()
marketplace_entries=()

for ptr_dir in "$SRC"/*/; do
  mp_name=$(basename "$ptr_dir")

  full_sha=$(cat "$ptr_dir/.commit-sha" 2>/dev/null || echo "")
  src_repo=$(cat "$ptr_dir/.source-repo" 2>/dev/null || echo "")

  if [ -z "$full_sha" ] || [ -z "$src_repo" ]; then
    echo "skip: $mp_name missing .commit-sha or .source-repo" >&2
    continue
  fi

  short_sha=${full_sha:0:12}
  workdir=/tmp/plugin-src/$mp_name
  rm -rf "$workdir"
  mkdir -p "$(dirname "$workdir")"

  echo "fetch: $mp_name ($src_repo @ $short_sha)"

  if [ -f "$ptr_dir/.sparse-paths" ]; then
    sparse_paths=$(cat "$ptr_dir/.sparse-paths")
    git clone --filter=blob:none --no-checkout "https://github.com/$src_repo" "$workdir"
    git -C "$workdir" sparse-checkout init --cone
    # shellcheck disable=SC2086
    git -C "$workdir" sparse-checkout set $sparse_paths
    git -C "$workdir" -c advice.detachedHead=false checkout "$full_sha"
  else
    git clone --filter=blob:none "https://github.com/$src_repo" "$workdir"
    git -C "$workdir" -c advice.detachedHead=false checkout "$full_sha"
  fi

  mp_json="$workdir/.claude-plugin/marketplace.json"
  if [ ! -f "$mp_json" ]; then
    echo "skip: $mp_name has no .claude-plugin/marketplace.json at $short_sha" >&2
    rm -rf "$workdir"
    continue
  fi

  # Copy the marketplace into marketplaces/<name> (without .git)
  cp -r "$workdir" "$PLUGINS/marketplaces/$mp_name"
  rm -rf "$PLUGINS/marketplaces/$mp_name/.git"

  marketplace_entries+=("$(jq -nc \
    --arg name "$mp_name" \
    --arg repo "$src_repo" \
    --arg loc "/home/claude/.claude/plugins/marketplaces/$mp_name" \
    --arg now "$NOW" \
    '{($name): {"source": {"source": "github", "repo": $repo}, "installLocation": $loc, "lastUpdated": $now}}')")

  # Enumerate plugins from marketplace.json
  plugin_count=$(jq '.plugins | length' "$mp_json")
  for i in $(seq 0 $((plugin_count - 1))); do
    pname=$(jq -r ".plugins[$i].name" "$mp_json")
    psrc=$(jq -r ".plugins[$i].source" "$mp_json")
    psrc=${psrc#./}
    psrc=${psrc%/}
    abs_src="$workdir/$psrc"
    [ -z "$psrc" ] && abs_src="$workdir"

    if [ -f "$abs_src/plugin.json" ]; then
      pjson="$abs_src/plugin.json"
    elif [ -f "$abs_src/.claude-plugin/plugin.json" ]; then
      pjson="$abs_src/.claude-plugin/plugin.json"
    else
      pjson=""
    fi

    if [ -n "$pjson" ]; then
      pver=$(jq -r '.version // empty' "$pjson")
    else
      pver=""
    fi
    [ -z "$pver" ] && pver="$short_sha"

    cache_dir="$PLUGINS/cache/$mp_name/$pname/$pver"
    mkdir -p "$cache_dir"
    cp -r "$abs_src/." "$cache_dir/"
    # If the plugin source is the repo root (source: "./"), the clone's .git
    # gets copied too — drop it (the partial-clone .promisor files are also
    # root-owned 0400 and would break the entrypoint's cp into $HOME).
    rm -rf "$cache_dir/.git"

    installed_entries+=("$(jq -nc \
      --arg key "$pname@$mp_name" \
      --arg path "/home/claude/.claude/plugins/cache/$mp_name/$pname/$pver" \
      --arg ver "$pver" \
      --arg now "$NOW" \
      --arg sha "$full_sha" \
      '{($key): [{"scope": "user", "installPath": $path, "version": $ver, "installedAt": $now, "lastUpdated": $now, "gitCommitSha": $sha}]}')")

    echo "  + $pname@$mp_name ($pver)"
  done

  rm -rf "$workdir"
done

# Merge into final JSON files
printf '%s\n' "${installed_entries[@]}" | jq -s 'reduce .[] as $x ({}; . * $x) | {version: 2, plugins: .}' > "$PLUGINS/installed_plugins.json"
printf '%s\n' "${marketplace_entries[@]}" | jq -s 'reduce .[] as $x ({}; . * $x)' > "$PLUGINS/known_marketplaces.json"

echo "Done. Marketplaces: ${#marketplace_entries[@]}, plugins: ${#installed_entries[@]}"
