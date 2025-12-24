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

ROM_VERSION="2.0.5"
export ROM_VERSION
export DEBUG_BUILD=false

BIN=$ASTROROM/utilities
export BIN

PROJECT_DIR="$ASTROROM/astro"
OBJECTIVES_DIR="$ASTROROM/objectives"

available_devices=()

if [[ -d "$OBJECTIVES_DIR" ]]; then
    for d in "$OBJECTIVES_DIR"/*/; do
        [[ -d "$d" ]] || continue
        available_devices+=("$(basename "$d")")
    done
fi

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
	
	if [[ "$cached_hash" == "$current_hash" ]]; then
        LOG_INFO "Skipping already applied script: $rel_path"
        return 0
    fi

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
    [[ ! -d "$OBJECTIVES_DIR" ]] && \
        ERROR_EXIT "OBJECTIVES_DIR not found: $OBJECTIVES_DIR"

    local devices=()
    for d in "$OBJECTIVES_DIR"/*/; do
        [[ -d "$d" ]] || continue
        devices+=("$(basename "$d")")
    done

    [[ ${#devices[@]} -eq 0 ]] && \
        ERROR_EXIT "No objectives found in $OBJECTIVES_DIR"

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
    
	rm -rf "$WORKSPACE"
	
    LOG_END "Build completed for $device"
}


show_usage() {
cat <<EOF

AstroROM Build Tool v${ROM_VERSION}
Copyright (c) 2025 Sameer Al Sahab

USAGE:
  sudo ./build.sh [options] [command] [device]

COMMANDS:
  -b, --build [device]      Build ROM for a specific device.
                            If [device] is not given, a selection menu will appear.
  -c, --clean [option]      Cleanup build artifacts.
  -h, --help                Show usage.

CLEAN OPTIONS:
  -f, --firmware            Remove downloaded firmware files.
  -w, --workspace           Remove the workspace directory.
  --workdir                 Remove the unpacked firmware directory.
  --all                     Perform a full cleanup (firmware + workspace + workdir).

OPTIONS:
  -d, --debug               Enable debug mode.

AVAILABLE OBJECTIVES:
  ${available_devices[*]:-None found in $OBJECTIVES_DIR}

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
			if [[ -n "$2" && "$2" != -* ]]; then
				device="$2"
				shift 2
			else
				shift 1
		    fi
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



