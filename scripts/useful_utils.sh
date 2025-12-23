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



_SANITIZE_PATH() {
    realpath -m --relative-to=. "$1" | sed 's|^/||; s|/$||'
}


GET_FEAT_STATUS() {
    local var_name="$1"
    local default="${2:-false}"


    if ! declare -p "$var_name" &>/dev/null; then
        ERROR_EXIT
    fi

    local val="${!var_name,,}"

    case "$val" in
        true|1|y|yes|on)
            return 0 ;;
        false|0|n|no|off|"")
            return 1 ;;
        *)
            LOG_WARN "Invalid value for $var_name='$val'"
            ERROR_EXIT ;;
    esac
}


#
# Usage: NUKE_BLOAT <KnoxGuard> <SamsungPass>
#
NUKE_BLOAT() {
    local targets=("$@")
	# We dont need more partitions as of now
    local partitions=("system" "product" "system_ext")
    local removed_count=0

    [[ ${#targets[@]} -eq 0 ]] && \
        ERROR_EXIT "Usage: NUKE_BLOAT <PackageName1> <PackageName2> ..."

    local targets_lc=()
    for t in "${targets[@]}"; do
        targets_lc+=("${t,,}")
    done

    for part in "${partitions[@]}"; do
        local part_path
        part_path=$(GET_PARTITION_PATH "$part" 2>/dev/null) || continue
        [[ ! -d "$part_path" ]] && continue

        _UPDATE_LOG "In ${WHITE}${part}${YELLOW} partition..."

        for subdir in app priv-app; do
            local base_dir="$part_path/$subdir"
            [[ ! -d "$base_dir" ]] && continue

            for folder in "$base_dir"/*; do
                [[ ! -d "$folder" ]] && continue

                local name
                name=$(basename "$folder")
                local name_lc="${name,,}"

                for target in "${targets_lc[@]}"; do
                    [[ "$name_lc" != "$target" ]] && continue

                    _UPDATE_LOG \
                        "Removing ${name}..."

                    if rm -rf "$folder" 2>/dev/null; then
                        ((removed_count++))
                    else
                        ERROR_EXIT "Failed to remove package: ${name}"
                    fi
                done
            done
        done
    done

    if [[ $removed_count -gt 0 ]]; then
        _UPDATE_LOG \
            "Successfully removed ${removed_count} packages." "DONE"
    else
        _UPDATE_LOG "No matching packages found." 
    fi

    return 0
}

#
# Adds/updates a unique entry to file_contexts
#
ADD_CONTEXT() {
    local partition="$1"
    local file_path="$2"
    local type="$3"

    [[ $# -lt 3 ]] && ERROR_EXIT "Usage: ADD_CONTEXT <partition> <file_path> <type>"

    local context_file="${CONFIG_DIR}/${partition}_file_contexts"


    [[ "$file_path" != /* ]] && file_path="/$file_path"

    type="${type%%:s0}"
    local context="u:object_r:${type}:s0"

    # Escape dots for regex
    local escaped_path
    escaped_path=$(printf '%s\n' "$file_path" | sed 's/\./\\./g')

    mkdir -p "$(dirname "$context_file")"
    touch "$context_file"

    local exact_entry="${escaped_path} ${context}"


    if grep -qxF "$exact_entry" "$context_file"; then
        return 0
    fi

    local tmp
    tmp=$(mktemp)

    local replaced=0
    while IFS= read -r line || [[ -n "$line" ]]; do

        if [[ "$line" =~ ^${escaped_path}[[:space:]] ]]; then
            if [[ $replaced -eq 0 ]]; then
                echo "$exact_entry" >> "$tmp"
                replaced=1
            fi
            continue
        fi
        echo "$line" >> "$tmp"
    done < "$context_file"


    [[ $replaced -eq 0 ]] && echo "$exact_entry" >> "$tmp"

    mv "$tmp" "$context_file"

    return 0
}

#
# Removes file frorm workspace
# Usage REMOVE "partition" "path"
#

REMOVE() {
    local partition="$1"
    local relative_path="$2"
    
    if [[ -z "$partition" || -z "$relative_path" ]]; then
        ERROR_EXIT "Missing arguments. Usage: REMOVE <partition> <path>"
    fi
    
    local base_dir
    base_dir=$(GET_PARTITION_PATH "$partition" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        ERROR_EXIT "Failed to get partition directory for '$partition'"
    fi
    
    local clean_path
    clean_path=$(_SANITIZE_PATH "$relative_path")

   
    local found_any=false
    
    
    for match in "${base_dir}"/$clean_path; do
      
        [[ ! -e "$match" && ! -L "$match" ]] && continue
        
        found_any=true
        
        # Remove from Disk
        if ! rm -rf "$match" 2>/dev/null; then
            ERROR_EXIT "Failed to remove '$match'"
        fi


        local actual_rel_path="${match#$base_dir/}"
        
        
        local escaped_path
        escaped_path=$(printf '%s' "$actual_rel_path" | sed 's/[.[\*^$()+?{|]/\\&/g')
        
        local fs_config_file="$WORKSPACE/config/${partition}_fs_config"
        local file_contexts_file="$WORKSPACE/config/${partition}_file_contexts"
        
        if [[ -f "$fs_config_file" ]]; then
            sed -i "\|^${partition}/${escaped_path}\(/\|[[:space:]]\)|d" "$fs_config_file"
        fi
        
        if [[ -f "$file_contexts_file" ]]; then
            sed -i "\|^/${partition}/${escaped_path}\(/\|[[:space:]]\)|d" "$file_contexts_file"
        fi
    done

    if [[ "$found_any" = false ]]; then
        LOG_WARN "No files matching '${partition}/${clean_path}' found to remove."
    fi
    
    return 0
}




#
# Apply hex patch to file
# Usage: HEX_EDIT "vendor/lib64/lib.so" "DEADBEEF" "CAFEBABE"
#

HEX_EDIT() {
    local rel_path="$1"
    local from_hex="$2"
    local to_hex="$3"
    local file="${WORKSPACE}/${rel_path}"

 
    if [[ -z "$rel_path" ]] || [[ -z "$from_hex" ]] || [[ -z "$to_hex" ]]; then
        ERROR_EXIT "Usage: HEX_EDIT <relative-path> <old-hex> <new-hex>"
        return 1
    fi

    if [[ ! -f "$file" ]]; then
        ERROR_EXIT "File not found: $rel_path"
        return 1
    fi

    # Normalize patterns to lowercase
    from_hex=$(tr '[:upper:]' '[:lower:]' <<< "$from_hex")
    to_hex=$(tr '[:upper:]' '[:lower:]' <<< "$to_hex")

    # Get file's hex dump
    local file_hex
    file_hex=$(xxd -p "$file" | tr -d '\n ')

    # Check if already patched
    if grep -q "$to_hex" <<< "$file_hex"; then
        LOG_INFO "Already patched: $rel_path"
        return 0
    fi


    if ! grep -q "$from_hex" <<< "$file_hex"; then
        ERROR_EXIT "Pattern not found in file: $from_hex"
        ERROR_EXIT "File: $rel_path"
        return 1
    fi

    LOG_INFO "Patching $from_hex → $to_hex in $rel_path"

    if echo "$file_hex" | sed "s/$from_hex/$to_hex/" | xxd -r -p > "${file}.tmp"; then
        mv "${file}.tmp" "$file"
        return 0
    else
        ERROR_EXIT "Failed to apply patch to $rel_path"
        rm -f "${file}.tmp"
        return 1
    fi
}



# Reference: https://source.android.com/docs/core/ota/apex
EXTRACT_FROM_APEX_PAYLOAD() {
    local apex_rel="$1"
    local lib_path="$2"
    local out_rel="$3"

    local apex_file="${WORKSPACE}/${apex_rel}"
    local out_file="${WORKSPACE}/${out_rel}"
    local tmp_dir="/tmp/apex_extract_$$"


    if [[ -f "$out_file" ]]; then
        LOG_INFO "Already extracted $out_rel"
        return 0
    fi

    if [[ ! -f "$apex_file" ]]; then
        ERROR_EXIT "APEX not found: $apex_rel"
    fi

    LOG_INFO "Extracting $lib_path from ${apex_rel##*/}..."


    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    
    if ! unzip -j "$apex_file" "apex_payload.img" -d "$tmp_dir" >/dev/null 2>&1; then
	    rm -rf "$tmp_dir"
        ERROR_EXIT "Failed to extract apex_payload.img from $apex_file"
    fi

    
    local lib_name
    lib_name=$(basename "$lib_path")
    local extracted=false

    
    if command -v 7z &>/dev/null; then
        if 7z e -y "$tmp_dir/apex_payload.img" "$lib_path" -o"$tmp_dir" >/dev/null 2>&1; then
            extracted=true
        fi
    fi

   
    if [[ "$extracted" == false ]] && command -v debugfs &>/dev/null; then
        if echo "dump $lib_path $tmp_dir/$lib_name" | debugfs "$tmp_dir/apex_payload.img" 2>/dev/null; then
            extracted=true
        fi
    fi

    
    if [[ "$extracted" == false ]] || [[ ! -f "$tmp_dir/$lib_name" ]]; then
	    rm -rf "$tmp_dir"
        ERROR_EXIT "Failed to extract $lib_path from apex_payload.img" 
    fi

    
    mkdir -p "$(dirname "$out_file")"
    if mv "$tmp_dir/$lib_name" "$out_file"; then
        LOG "Extracted to $out_rel"
    else
	    rm -rf "$tmp_dir"
        ERROR_EXIT "Failed to move extracted file to: $out_rel"
    fi

    rm -rf "$tmp_dir"
    return 0
}

