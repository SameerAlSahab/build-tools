#!/usr/bin/env bash
#
#  Copyright (c) 2025 Sameer Al Sahab
#  Licensed under the MIT License. See LICENSE file for details.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#


set -o pipefail
export BASH_WARN_ON_NULL=0


ASTROROM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ASTROROM

ROM_VERSION="2.0.4"
export ROM_VERSION
export DEBUG_BUILD=false

BIN=$ASTROROM/utilities
export BIN

PROJECT_DIR="$ASTROROM/astro"
OBJECTIVES_DIR="$ASTROROM/objectives"

export WORKDIR="$ASTROROM/firmware/unpacked"
WORKSPACE="$ASTROROM/workspace"
DIROUT="$ASTROROM/out"

MARKER_FILE="$WORKSPACE/.build_markers"

PLATFORM=""
CODENAME=""


for util in "$ASTROROM"/scripts/*.sh; do
    [[ -f "$util" ]] && source "$util"
done



EXEC_SCRIPT() {
    local script_file="$1"
    local marker="$2"

    export SCRPATH
    SCRPATH=$(cd "$(dirname "$script_file")" && pwd)
    
    local rel_path="${script_file#$ASTROROM/}"

    local current_hash cached_hash
    current_hash=$(md5sum "$script_file" 2>/dev/null | awk '{print $1}')
    [[ -z "$current_hash" ]] && ERROR_EXIT "Hash failed: $rel_path"

    cached_hash=$(grep -F "$script_file" "$marker" 2>/dev/null | awk '{print $2}')
    [[ "$cached_hash" == "$current_hash" ]] && return 0

    LOG_INFO "Applying: $rel_path"

    if ! source "$script_file"; then
        local rc=$?
        ERROR_EXIT "Script failed in $rel_path (exit $rc)"
    fi

    unset SCRPATH

    mkdir -p "$(dirname "$marker")"
    sed -i "\|^$script_file |d" "$marker" 2>/dev/null || true
    echo "$script_file $current_hash" >> "$marker"
}


_BUILD_WORKFLOW() {


    if [[ -z "$device" ]]; then
        local devices=()
        for d in "$OBJECTIVES_DIR"/*/; do
            devices+=("$(basename "$d")")
        done
        local choice=$(_CHOICE "Available objectives" "${devices[@]}")
        device="${devices[choice-1]}"
    fi

    OBJECTIVE="$OBJECTIVES_DIR/$device"
    export OBJECTIVE

    source "$OBJECTIVE/$device.sh" || ERROR_EXIT "Device config load failed"

    SETUP_DEVICE_ENV || ERROR_EXIT "Env setup failed"

    
    local layers=(
        "$OBJECTIVE"
        "$PROJECT_DIR"
        "$PROJECT_DIR/platform/$PLATFORM"
    )

for layer in "${layers[@]}"; do
    [[ ! -d "$layer" ]] && continue

    
    while IFS= read -r -d '' sh; do
        [[ "$sh" == *"$device.sh" ]] && continue
        EXEC_SCRIPT "$sh" "$MARKER_FILE"
    done < <(find "$layer" -type f -name "*.sh" \
        ! -path "*.apk/*" \
        ! -path "*.jar/*" \
        -print0 | sort -z)

    
    while IFS= read -r -d '' img; do
        part=$(basename "$img" .img)
        if target=$(GET_PARTITION_PATH "$part" 2>/dev/null); then
            mkdir -p "$target"
            sudo rsync -a --no-links "$img/" "$target/" \
                || ERROR_EXIT "Partition sync failed $part"
        else
            LOG_WARN "Unknown partition. Ignoring.. $part"
        fi
    done < <(find "$layer" -type d -name "*.img" -print0)
done

    _APKTOOL_PATCH || ERROR_EXIT "APK/JAR patching failed"

    REPACK_ROM "$FILESYSTEM" || ERROR_EXIT "Repack failed"

    LOG_END "Build completed: $device"
}


show_usage() {
cat <<EOF

AstroROM Build v${ROM_VERSION}

USAGE:
  build.sh <command> [options] [device]

COMMANDS:
  build [device]        Build ROM for a device (will ask if not given)
  clean [options]       Remove build artifacts
  help                  Show this help message

CLEAN OPTIONS:
  -f, --firmware        Remove firmware downloads
  -w, --workspace       Remove workspace
      --workdir         Remove unpacked firmware
      --all             Remove everything

EXAMPLES:
  sudo ./build.sh build x1q
  sudo ./build.sh build
  sudo ./build.sh clean --workspace
  sudo ./build.sh clean --all

NOTE:
  Root privileges are required for build and clean operations.

EOF
}


cleanup_workspace() {
    local targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--firmware)  targets+=("$FW_DIR") ;;
            -w|--workspace) targets+=("$WORKSPACE") ;;
            --workdir)      targets+=("$WORKDIR") ;;
            --all)
                targets+=("$FW_DIR" "$WORKSPACE" "$WORKDIR")
                ;;
            *)
                LOG_WARN "Unknown clean option: $1"
                ;;
        esac
        shift
    done

    [[ ${#targets[@]} -eq 0 ]] && {
        LOG_WARN "Nothing to clean"
        return 0
    }

    for path in "${targets[@]}"; do
        [[ -d "$path" ]] || continue
        LOG_INFO "Removing ${path#$ASTROROM/}"
        rm -rf "$path" || ERROR_EXIT "Failed to remove $path"
    done

    rm -f "$MARKER_FILE" 2>/dev/null || true
    LOG "Cleanup completed"
}



device=""


while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug|-d)
            DEBUG_BUILD=true
            shift 
            ;;
        --build|-b)
            
            device="$2"
            shift 2 
            ;;
        --clean|-c)
          
            cleanup_workspace "${@:2}"
            exit 0
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
          
            if [[ -z "$device" ]]; then
                device="$1"
            fi
            shift
            ;;
    esac
done


[[ $EUID -ne 0 ]] && ERROR_EXIT "Root required"

_BUILD_WORKFLOW


chown -R -h "$SUDO_USER:$SUDO_USER" \
    "$WORKSPACE" "$WORKDIR" "$DIROUT" "$FW_DIR" 2>/dev/null || true

LOG_DIALOG "Completed everything" "Build finished for $device"



