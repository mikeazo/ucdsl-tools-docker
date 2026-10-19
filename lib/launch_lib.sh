#!/usr/bin/env bash
# Shared implementation for launch.sh. This file is intentionally sourceable by
# tests; launch.sh supplies strict Bash options and repository-relative defaults.

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SCRIPT_DIR:=$(cd "$LIB_DIR/.." && pwd)}"
: "${CONFIG_DIR:=$SCRIPT_DIR/configvolumes}"
: "${OUTPUT_DIR:=$SCRIPT_DIR/outputlogs}"

readonly CLI_CONTAINER="ucdsl-cli"
readonly GUI_CONTAINER="ucdsl-gui"
readonly CLI_IMAGE="ucdsl-tools"
readonly GUI_IMAGE="ucdsl-tools-gui"
readonly CLI_DOCKERFILE="ucdsl.Dockerfile"
readonly GUI_DOCKERFILE="ucdsl-gui.Dockerfile"
readonly CLI_SOURCE_DEST="/host/srcfiles"
readonly CLI_INCLUDES_DEST="/host/includes"
readonly GUI_SOURCE_DEST="/home/headless/srcfiles"
readonly GUI_INCLUDES_DEST="/home/headless/includes"
readonly UCDSL_PATH="/home/primary/EasyUC/uc-dsl/bin/ucdsl"

MODE=""
SOURCE_SPEC=""
INCLUDES_SPEC=""
SOURCE_NAME=""
INCLUDES_NAME=""
IMAGE_SOURCE=""
CLI_UCI=""
NON_INTERACTIVE=0
DOCKERHUB_USER="${DOCKERHUB_USER:-mikeazo}"
RESOLVED_SOURCE=""
RESOLVED_INCLUDES=""
STARTED_CONTAINER=""

usage() {
    cat <<'EOF'
Usage: ./launch.sh [options]

Launch the UC-DSL CLI or GUI container. With no options, the script guides you
through the same interactive workflow as earlier versions.

Options:
  --mode cli|gui              Launch mode.
  --source ALIAS|ABSOLUTE_PATH
                              Source-code mount alias or absolute directory.
  --includes ALIAS|ABSOLUTE_PATH|none
                              Includes mount alias, absolute directory, or none.
  --source-name NAME          Alias to save for a new source path.
  --includes-name NAME        Alias to save for a new includes path.
  --image-source pull|build   Pull the hosted image or build it locally.
  --uci FILE                 Top-level .uci file to run in CLI mode.
  --dockerhub-user USER       Docker Hub namespace (default: DOCKERHUB_USER or
                              mikeazo).
  --non-interactive           Fail instead of prompting for missing values.
  -h, --help                  Show this help.

Aliases are stored as configvolumes/NAME.txt and remain compatible with the
previous launch script.
EOF
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

read_prompt() {
    local prompt="$1"
    local __result_var="$2"
    local value

    if (( NON_INTERACTIVE )); then
        die "missing required option for non-interactive mode"
    fi

    read -r -e -p "$prompt" value || die "input cancelled"
    printf -v "$__result_var" '%s' "$value"
}

validate_mode() {
    case "$MODE" in
        cli|gui) ;;
        "") read_prompt "Select a mode (cli or gui): " MODE; validate_mode ;;
        *) die "mode must be 'cli' or 'gui' (got '$MODE')" ;;
    esac
}

validate_image_source() {
    case "$IMAGE_SOURCE" in
        pull|build) ;;
        "")
            if (( NON_INTERACTIVE )); then
                die "--image-source is required in non-interactive mode"
            fi
            local choice
            read -r -p "Pull the hosted image or build locally? [p/B] " choice || die "input cancelled"
            case "$choice" in
                p|P) IMAGE_SOURCE="pull" ;;
                *) IMAGE_SOURCE="build" ;;
            esac
            ;;
        *) die "image source must be 'pull' or 'build' (got '$IMAGE_SOURCE')" ;;
    esac
}

validate_alias_name() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] ||
        die "alias '$name' may contain only letters, numbers, hyphens, and underscores"
}

validate_directory() {
    local path="$1"
    [[ "$path" == /* ]] || die "path must be absolute: '$path'"
    [[ -d "$path" ]] || die "directory does not exist: '$path'"
}

ensure_directories() {
    [[ -d "$CONFIG_DIR" ]] || die "configuration directory does not exist: '$CONFIG_DIR'"
    mkdir -p "$OUTPUT_DIR"
}

list_aliases() {
    local file
    local aliases=()

    shopt -s nullglob
    local alias
    for file in "$CONFIG_DIR"/*.txt; do
        alias="${file##*/}"
        alias="${alias%.txt}"
        [[ "$alias" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || continue
        aliases+=("$alias")
    done
    shopt -u nullglob

    if ((${#aliases[@]})); then
        printf '%s\n' "${aliases[@]}"
    else
        printf '(none)\n'
    fi
}

read_alias() {
    local name="$1"
    local file="$CONFIG_DIR/$name.txt"
    local source

    [[ -f "$file" ]] || return 1
    source="$(awk '/^src=/{sub(/^src=/, ""); print; exit}' "$file")"
    [[ -n "$source" ]] || die "alias '$name' does not contain an src= path"
    printf '%s' "$source"
}

save_alias() {
    local name="$1"
    local path="$2"
    local file

    validate_alias_name "$name"
    file="$CONFIG_DIR/$name.txt"
    [[ ! -e "$file" ]] || die "alias '$name' already exists"
    printf 'src=%s\n' "$path" > "$file"
}

prompt_for_alias_name() {
    local kind="$1"
    local __result_var="$2"
    local name

    read_prompt "Enter a unique name for the $kind volume: " name
    validate_alias_name "$name"
    printf -v "$__result_var" '%s' "$name"
}

# Resolve an alias or an absolute directory. A previously unknown absolute
# directory is saved under the supplied name, or prompts for one interactively.
resolve_location() {
    local kind="$1"
    local spec="$2"
    local requested_name="$3"
    local __result_var="$4"
    local path=""
    local alias_name=""

    if [[ -z "$spec" ]]; then
        if (( NON_INTERACTIVE )); then
            die "--$kind is required in non-interactive mode"
        fi
        printf 'Currently available volumes:\n' >&2
        list_aliases >&2
        read_prompt "Select $kind volume from list or enter a new absolute path to bind: " spec
    fi

    if [[ "$spec" == /* ]]; then
        path="$spec"
        validate_directory "$path"

        # Existing paths may be re-used without creating another alias.
        local candidate
        while IFS= read -r candidate; do
            if [[ "$(read_alias "$candidate")" == "$path" ]]; then
                printf -v "$__result_var" '%s' "$path"
                return
            fi
        done < <(list_aliases)

        alias_name="$requested_name"
        if [[ -z "$alias_name" ]]; then
            if (( NON_INTERACTIVE )); then
                die "--${kind}-name is required to save new path '$path'"
            fi
            prompt_for_alias_name "$kind" alias_name
        fi
        save_alias "$alias_name" "$path"
    else
        validate_alias_name "$spec"
        path="$(read_alias "$spec")" || die "unknown $kind alias: '$spec'"
        validate_directory "$path"
    fi

    printf -v "$__result_var" '%s' "$path"
}

resolve_includes() {
    if [[ "$INCLUDES_SPEC" == "none" ]]; then
        RESOLVED_INCLUDES=""
        return
    fi

    if [[ -z "$INCLUDES_SPEC" ]] && (( ! NON_INTERACTIVE )); then
        printf 'Currently available volumes:\n' >&2
        list_aliases >&2
        read_prompt "Select includes volume from list or enter a new absolute path to bind (blank for none): " INCLUDES_SPEC
        if [[ -z "$INCLUDES_SPEC" ]]; then
            RESOLVED_INCLUDES=""
            return
        fi
    fi

    resolve_location "includes" "$INCLUDES_SPEC" "$INCLUDES_NAME" RESOLVED_INCLUDES
}

parse_args() {
    while (($#)); do
        case "$1" in
            --mode)
                [[ $# -ge 2 && -n "$2" ]] || die "--mode requires a value"
                MODE="$2"; shift 2
                ;;
            --source)
                [[ $# -ge 2 && -n "$2" ]] || die "--source requires a value"
                SOURCE_SPEC="$2"; shift 2
                ;;
            --includes)
                [[ $# -ge 2 && -n "$2" ]] || die "--includes requires a value"
                INCLUDES_SPEC="$2"; shift 2
                ;;
            --source-name)
                [[ $# -ge 2 && -n "$2" ]] || die "--source-name requires a value"
                SOURCE_NAME="$2"; shift 2
                ;;
            --includes-name)
                [[ $# -ge 2 && -n "$2" ]] || die "--includes-name requires a value"
                INCLUDES_NAME="$2"; shift 2
                ;;
            --image-source)
                [[ $# -ge 2 && -n "$2" ]] || die "--image-source requires a value"
                IMAGE_SOURCE="$2"; shift 2
                ;;
            --uci)
                [[ $# -ge 2 && -n "$2" ]] || die "--uci requires a value"
                CLI_UCI="$2"; shift 2
                ;;
            --dockerhub-user)
                [[ $# -ge 2 && -n "$2" ]] || die "--dockerhub-user requires a value"
                DOCKERHUB_USER="$2"; shift 2
                ;;
            --non-interactive) NON_INTERACTIVE=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1 (use --help)" ;;
        esac
    done

    [[ -n "$DOCKERHUB_USER" ]] || die "Docker Hub user must not be empty"
}

check_docker() {
    command -v docker >/dev/null 2>&1 || die "Docker is not installed or not on PATH"
    docker info >/dev/null 2>&1 || die "Docker is not running or is not accessible"
}

ensure_container_is_available() {
    local name="$1"
    local existing

    existing="$(docker ps -aq --filter "name=^/${name}$")"
    [[ -z "$existing" ]] ||
        die "container '$name' already exists; stop or remove it before launching"
}

prepare_image() {
    local local_name="$1"
    local dockerfile="$2"

    validate_image_source
    case "$IMAGE_SOURCE" in
        pull)
            docker pull "${DOCKERHUB_USER}/${local_name}:latest"
            docker tag "${DOCKERHUB_USER}/${local_name}:latest" "$local_name"
            printf 'Pulled %s/%s:latest (architecture selected automatically by Docker).\n' \
                "$DOCKERHUB_USER" "$local_name"
            ;;
        build)
            docker build -t "$local_name" -f "$dockerfile" "$SCRIPT_DIR"
            ;;
    esac
}

choose_uci_file() {
    local file

    if [[ -n "$CLI_UCI" ]]; then
        file="$CLI_UCI"
        CLI_UCI=""
        [[ "$file" != */* && "$file" == *.uci && -f "$RESOLVED_SOURCE/$file" ]] ||
            die "--uci must name an existing top-level .uci file in the source directory"
        printf '%s' "$file"
        return
    fi

    while true; do
        read_prompt "Enter a *.uci file to run: " file
        [[ "$file" != */* && "$file" == *.uci && -f "$RESOLVED_SOURCE/$file" ]] && {
            printf '%s' "$file"
            return
        }
        printf "Choose an existing top-level .uci file from '%s'.\n" "$RESOLVED_SOURCE" >&2
    done
}

run_cli() {
    local -a docker_args=(run --rm -d -i -t --name "$CLI_CONTAINER" --volume "$RESOLVED_SOURCE:$CLI_SOURCE_DEST")
    local uci_script log_file response status

    ensure_container_is_available "$CLI_CONTAINER"
    if [[ -n "$RESOLVED_INCLUDES" ]]; then
        docker_args+=(--volume "$RESOLVED_INCLUDES:$CLI_INCLUDES_DEST")
    fi
    docker_args+=("$CLI_IMAGE" /bin/bash)
    docker "${docker_args[@]}"
    STARTED_CONTAINER="$CLI_CONTAINER"

    printf 'All UCI files in volume:\n'
    (
        cd "$RESOLVED_SOURCE" || exit 1
        shopt -s nullglob
        printf '%s\n' *.uci
    )

    while true; do
        uci_script="$(choose_uci_file)"
        log_file="$OUTPUT_DIR/${uci_script%.uci}_out.txt"
        if [[ -n "$RESOLVED_INCLUDES" ]]; then
            if docker exec -i "$CLI_CONTAINER" bash -c 'exec "$@"' -- \
                "$UCDSL_PATH" -I "$CLI_INCLUDES_DEST" "$CLI_SOURCE_DEST/$uci_script" >"$log_file" 2>&1; then
                status=0
            else
                status=$?
            fi
        else
            if docker exec -i "$CLI_CONTAINER" bash -c 'exec "$@"' -- \
                "$UCDSL_PATH" "$CLI_SOURCE_DEST/$uci_script" >"$log_file" 2>&1; then
                status=0
            else
                status=$?
            fi
        fi
        if [[ "$status" -eq 0 ]]; then
            printf 'Output written to %s\n' "$log_file"
        else
            printf 'UC DSL exited with code %s; output written to %s\n' "$status" "$log_file" >&2
        fi

        if (( NON_INTERACTIVE )); then
            break
        fi
        read_prompt "Do you want to run another script? [y/N]: " response
        [[ "$response" == "y" || "$response" == "Y" ]] || break
    done
}

run_gui() {
    local -a docker_args=(run --rm --name "$GUI_CONTAINER" --volume "$RESOLVED_SOURCE:$GUI_SOURCE_DEST")

    ensure_container_is_available "$GUI_CONTAINER"
    if [[ -n "$RESOLVED_INCLUDES" ]]; then
        docker_args+=(--volume "$RESOLVED_INCLUDES:$GUI_INCLUDES_DEST")
    fi
    docker_args+=(-p "36901:6901" -p "35901:5901" "$GUI_IMAGE" /bin/bash)

    printf 'To connect to the GUI, open http://localhost:36901/vnc.html?password=headless\n'
    STARTED_CONTAINER="$GUI_CONTAINER"
    docker "${docker_args[@]}"
    STARTED_CONTAINER=""
}

cleanup() {
    if [[ -n "$STARTED_CONTAINER" ]]; then
        docker rm -f "$STARTED_CONTAINER" >/dev/null 2>&1 || true
        STARTED_CONTAINER=""
    fi
}

main() {
    parse_args "$@"
    validate_mode
    if [[ "$MODE" == "cli" && "$NON_INTERACTIVE" -eq 1 && -z "$CLI_UCI" ]]; then
        die "--uci is required for non-interactive CLI mode"
    fi
    ensure_directories
    check_docker
    trap cleanup EXIT INT TERM

    resolve_location "source" "$SOURCE_SPEC" "$SOURCE_NAME" RESOLVED_SOURCE
    resolve_includes

    case "$MODE" in
        cli)
            prepare_image "$CLI_IMAGE" "$CLI_DOCKERFILE"
            run_cli
            ;;
        gui)
            prepare_image "$GUI_IMAGE" "$GUI_DOCKERFILE"
            run_gui
            ;;
    esac

    printf 'End of launch script\n'
}
