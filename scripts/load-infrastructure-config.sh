#!/bin/bash
# Shared infrastructure config resolution and loading for setup, validate, and test scripts.
#
# Resolution order (first match wins):
#   1. INFRA_CONFIG — path to the file (absolute or relative to repo root)
#   2. cli_config argument — explicit path from --config FILE
#   3. cli_env argument or INFRA_ENV — repo root file config.<NAME>.env
#   4. Default — config.env in repo root
#
# After a successful load, INFRA_CONFIG_PATH is set to the absolute path of the file that was sourced.

infrastructure_config_normalize_path() {
    local repo_root="${1:?}"
    local path="${2:?}"
    if [[ "$path" != /* ]]; then
        path="${repo_root%/}/${path#./}"
    fi
    local dir
    dir=$(dirname "$path")
    local base
    base=$(basename "$path")
    if [ ! -d "$dir" ]; then
        echo "$path"
        return 0
    fi
    echo "$(cd "$dir" && pwd)/$base"
}

# Args: repo_root [cli_config] [cli_env]
# Prints absolute path to the config file (may not exist yet).
infrastructure_config_resolve_path() {
    local repo_root="${1:?}"
    local cli_config="${2:-}"
    local cli_env="${3:-}"
    local path

    if [ -n "${INFRA_CONFIG:-}" ]; then
        infrastructure_config_normalize_path "$repo_root" "${INFRA_CONFIG}"
        return 0
    fi
    if [ -n "$cli_config" ]; then
        infrastructure_config_normalize_path "$repo_root" "$cli_config"
        return 0
    fi
    local name="${cli_env:-${INFRA_ENV:-}}"
    if [ -n "$name" ]; then
        echo "${repo_root}/config.${name}.env"
        return 0
    fi
    echo "${repo_root}/config.env"
}

infrastructure_config_print_not_found() {
    local path="$1"
    local repo_root="$2"
    echo "Configuration file not found: $path" >&2
    echo "Resolution order: INFRA_CONFIG, --config FILE, --env NAME or INFRA_ENV (config.NAME.env), default config.env" >&2
    echo "Create from example:" >&2
    echo "  cp ${repo_root}/config.env.example ${repo_root}/config.env" >&2
    echo "Or for a named environment:" >&2
    echo "  cp ${repo_root}/config.env.example ${repo_root}/config.<name>.env" >&2
}

# Args: repo_root [cli_config] [cli_env]
# Sources the resolved file; exports INFRA_CONFIG_PATH. Returns non-zero if file is missing.
infrastructure_config_load() {
    local repo_root="${1:?}"
    local cli_config="${2:-}"
    local cli_env="${3:-}"
    local path
    path=$(infrastructure_config_resolve_path "$repo_root" "$cli_config" "$cli_env")
    if [ ! -f "$path" ]; then
        infrastructure_config_print_not_found "$path" "$repo_root"
        return 1
    fi
    export INFRA_CONFIG_PATH="$path"
    # shellcheck disable=SC1090
    source "$path"
}

# Source config if the resolved file exists; otherwise continue without error (for early validate steps).
infrastructure_config_load_optional() {
    local repo_root="${1:?}"
    local path
    path=$(infrastructure_config_resolve_path "$repo_root" "" "")
    if [ -f "$path" ]; then
        export INFRA_CONFIG_PATH="$path"
        # shellcheck disable=SC1090
        source "$path"
    fi
}

# After parsing CLI in an entry script, export INFRA_CONFIG so child processes use the same file.
infrastructure_config_export_for_children() {
    local repo_root="${1:?}"
    local cli_config="${2:-}"
    local cli_env="${3:-}"
    local path
    path=$(infrastructure_config_resolve_path "$repo_root" "$cli_config" "$cli_env")
    export INFRA_CONFIG="$path"
}
