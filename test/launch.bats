#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_ROOT="$BATS_TEST_TMPDIR/launch-test"
    CONFIG_DIR="$TEST_ROOT/configvolumes"
    OUTPUT_DIR="$TEST_ROOT/outputlogs"
    SOURCE_DIR="$TEST_ROOT/source"
    MOCK_BIN="$TEST_ROOT/bin"
    DOCKER_LOG="$TEST_ROOT/docker.log"

    mkdir -p "$CONFIG_DIR" "$OUTPUT_DIR" "$SOURCE_DIR" "$MOCK_BIN"
    touch "$SOURCE_DIR/example.uci"

    cat > "$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_LOG"
case "$1" in
    info|pull|tag|build|run|exec|rm) exit 0 ;;
    ps) exit 0 ;;
esac
EOF
    chmod +x "$MOCK_BIN/docker"

    export CONFIG_DIR OUTPUT_DIR DOCKER_LOG
    export PATH="$MOCK_BIN:$PATH"
}

@test "non-interactive GUI pulls an image and uses configured mounts" {
    run "$PROJECT_ROOT/launch.sh" \
        --non-interactive \
        --mode gui \
        --source "$SOURCE_DIR" --source-name example \
        --includes none \
        --image-source pull

    [ "$status" -eq 0 ]
    [ "$(cat "$CONFIG_DIR/example.txt")" = "src=$SOURCE_DIR" ]
    grep -F "pull mikeazo/ucdsl-tools-gui:latest" "$DOCKER_LOG"
    grep -F "run --rm --name ucdsl-gui --volume $SOURCE_DIR:/home/headless/srcfiles" "$DOCKER_LOG"
}

@test "existing aliases are resolved without creating a second alias" {
    printf 'src=%s\n' "$SOURCE_DIR" > "$CONFIG_DIR/existing.txt"

    run "$PROJECT_ROOT/launch.sh" \
        --non-interactive \
        --mode gui \
        --source existing \
        --includes none \
        --image-source build

    [ "$status" -eq 0 ]
    [ "$(find "$CONFIG_DIR" -name '*.txt' | wc -l | tr -d ' ')" -eq 1 ]
    grep -F "build -t ucdsl-tools-gui -f ucdsl-gui.Dockerfile $PROJECT_ROOT" "$DOCKER_LOG"
}

@test "a new non-interactive source path requires an alias name" {
    run "$PROJECT_ROOT/launch.sh" \
        --non-interactive \
        --mode gui \
        --source "$SOURCE_DIR" \
        --includes none \
        --image-source pull

    [ "$status" -ne 0 ]
    [[ "$output" == *"--source-name is required"* ]]
}

@test "non-interactive CLI runs the requested file with an includes mount and cleans up" {
    local includes_dir="$TEST_ROOT/includes"
    mkdir -p "$includes_dir"

    run "$PROJECT_ROOT/launch.sh" \
        --non-interactive \
        --mode cli \
        --source "$SOURCE_DIR" --source-name source \
        --includes "$includes_dir" --includes-name includes \
        --image-source build \
        --uci example.uci

    [ "$status" -eq 0 ]
    grep -F "run --rm -d -i -t --name ucdsl-cli --volume $SOURCE_DIR:/host/srcfiles --volume $includes_dir:/host/includes" "$DOCKER_LOG"
    grep -F "exec -i ucdsl-cli bash -c exec \"\$@\" -- /home/primary/EasyUC/uc-dsl/bin/ucdsl -I /host/includes /host/srcfiles/example.uci" "$DOCKER_LOG"
    grep -F "rm -f ucdsl-cli" "$DOCKER_LOG"
    [ -f "$OUTPUT_DIR/example_out.txt" ]
}

@test "invalid modes fail before Docker commands are issued" {
    run "$PROJECT_ROOT/launch.sh" \
        --non-interactive \
        --mode invalid \
        --source "$SOURCE_DIR" --source-name example \
        --includes none \
        --image-source pull

    [ "$status" -ne 0 ]
    [[ "$output" == *"mode must be 'cli' or 'gui'"* ]]
    [ ! -f "$DOCKER_LOG" ]
}
