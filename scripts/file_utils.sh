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

_GET_FILE_INODE() {
    local file_path="$1"
	# Returns inode only
    stat -c "%i" "$file_path" 2>/dev/null || echo ""
}

_GET_MD5_HASH() {
    local file_path="$1"
    md5sum "$file_path" 2>/dev/null | awk '{print $1}' | tr -d '[:space:]'
}

_GET_FILE_STAT() {
    local file_path="$1"
    # %i=inode, %s=size, %Y=mtime
    stat -c "%i.%s.%Y" "$file_path" 2>/dev/null || echo "unknown"
}

#
# FETCH_FILE <container> <target_file> <output_directory>
#
FETCH_FILE() {
    local container="$1"
    local target_file="$2"
    local out_dir="$3"
    local depth="${4:-0}"

    [[ -f "$container" ]] || return 1
    mkdir -p "$out_dir"

    local out_path="$out_dir/$target_file"
    [[ -s "$out_path" ]] && return 0

    (( depth >= 5 )) && return 1

    if [[ -z "${IS_DEPS_OK:-}" ]]; then
        COMMAND_EXISTS 7z  || CHECK_DEPENDENCY p7zip-full "7zip" true
        COMMAND_EXISTS lz4 || CHECK_DEPENDENCY lz4 "lz4" true
        IS_DEPS_OK=1
    fi

    LOG_INFO "Fetching $target_file from $(basename "$container") (Depth: $depth)"

    local file_list
    file_list="$(7z l "$container" 2>/dev/null)" || return 1

    
    if echo "$file_list" | awk '{print $NF}' | grep -Fxq "$target_file"; then
        7z x "$container" "$target_file" -so 2>/dev/null > "$out_path"
        [[ -s "$out_path" ]] && return 0
        rm -f "$out_path"
    fi

   
    if echo "$file_list" | awk '{print $NF}' | grep -Fxq "$target_file.lz4"; then
        if 7z x "$container" "$target_file.lz4" -so 2>/dev/null \
            | lz4 -d -c > "$out_path"; then
            [[ -s "$out_path" ]] && return 0
        fi
        rm -f "$out_path"
    fi

  
    echo "$file_list" | awk '{print $NF}' \
        | grep -E '\.(tar(\.md5)?|zip|lz4|bin|img|7z|xz|gz)$' \
        | while read -r node; do

        local tmp_node
        tmp_node="$(mktemp "$out_dir/tmp_$(basename "$node").XXXXXX")"

        7z x "$container" "$node" -so 2>/dev/null > "$tmp_node" || {
            rm -f "$tmp_node"
            continue
        }

        if FETCH_FILE "$tmp_node" "$target_file" "$out_dir" "$((depth + 1))"; then
            rm -f "$tmp_node"
            exit 0
        fi

        rm -f "$tmp_node"
    done

    return 1
}

#
# Checks if a file exists or not in a firmware partition
#
EXISTS() {
    local source_firmware
    local partition_name
    local target_path

    if [[ $# -eq 2 ]]; then
        source_firmware=""
        partition_name="$1"
        target_path="$2"
    elif [[ $# -eq 3 ]]; then
        source_firmware="$1"
        partition_name="$2"
        target_path="$3"
    else
        ERROR_EXIT "Usage: EXISTS [source] <partition> <path>"
        return 1
    fi

    local base_dir
    base_dir=$(GET_PARTITION_PATH "$partition_name" "$source_firmware" 2>/dev/null) || return 1
    [[ ! -d "$base_dir" ]] && return 1

    local sanitized_path
    sanitized_path=$(_SANITIZE_PATH "$target_path")

    for match in "$base_dir"/$sanitized_path; do
        [[ -e "$match" ]] && return 0
    done

    return 1
}

#
# Adds a file from another firmware
# ADD_FROM_FW "source" "partition" "path" [dest]
#
ADD_FROM_FW() {
    local source_type="$1"     
    local src_partition="$2"    
    local src_path="$3"         
    local dest_partition="${4:-$src_partition}" 

    
    if [[ -z "$source_type" ]] || [[ -z "$src_partition" ]] || [[ -z "$src_path" ]]; then
        ERROR_EXIT "Usage: COPY_FW <source_type> <src_partition> <src_path> [dest_partition]"
    fi

    
    local src_base
    src_base=$(GET_FW_DIR "$source_type" 2>/dev/null) || {
        ERROR_EXIT "Failed to resolve source workdir for: $source_type"
    }

    
    if ! VALIDATE_WORKDIR "$source_type"; then
        ERROR_EXIT "Source workdir '$source_type' is not ready: $src_base"
    fi

    
    local src_dir="${src_base}/${src_partition}"
    if [[ "$src_partition" == "system" ]]; then
        src_dir="${src_base}/system/system"
    fi

  
    local dest_dir="${WORKSPACE}/${dest_partition}"
    if [[ "$dest_partition" == "system" ]]; then
        dest_dir="${WORKSPACE}/system/system"
    fi

    
    if [[ ! -d "$src_dir" ]]; then
        ERROR_EXIT "Source directory does not exist: $src_dir"
        return 1
    fi

    if [[ ! -d "$dest_dir" ]]; then
        ERROR_EXIT "Destination directory does not exist: $dest_dir"
        return 1
    fi

    
    local clean_src_path
    clean_src_path=$(_SANITIZE_PATH "$src_path")
    local full_src="${src_dir}/${clean_src_path}"
    local full_dest="${dest_dir}/${clean_src_path}"

    
    if [[ ! -e "$full_src" ]] && [[ ! -L "$full_src" ]]; then
        LOG "Source file does not exist: $full_src"
		return 0
    fi

    
    local dest_parent
    dest_parent=$(dirname "$full_dest")
    if [[ ! -d "$dest_parent" ]]; then
        mkdir -p "$dest_parent" || {
            ERROR_EXIT "Failed to create destination directory: $dest_parent"
        }
    fi

    
    if [[ -e "$full_dest" ]]; then
        rm -rf "$full_dest" 2>/dev/null
    fi

    
    if cp -r "$full_src" "$full_dest" 2>/dev/null; then
        return 0
    else
        ERROR_EXIT "Failed copying ${src_partition}/${clean_src_path} from ${source_type}"
    fi
}

# 
# Usage: ADD "partition_name" "source_path" "relative_dest_path" [log_label]
#

ADD() {
    local partition="$1"
    local src_path="$2"
    local dest_rel_path="$3"
    local log_label="${4:-$(basename "$src_path")}" 

   
    local part_root
    part_root=$(GET_PARTITION_PATH "$partition") || {
        ERROR_EXIT "COPY failed: Could not resolve partition '$partition'."
        return 1
    }

    
    local full_dest="${part_root}/${dest_rel_path}"
    
  
    if [[ "$src_path" == "$full_dest" ]]; then
        LOG_WARN "Source and destination are identical. Skipping."
        return 0
    fi


    if [[ ! -e "$src_path" ]]; then
        local split_files=()
        
       
        if ls "${src_path}."* >/dev/null 2>&1; then
            split_files=("${src_path}."*)
        elif ls "${src_path}_"* >/dev/null 2>&1; then
            split_files=("${src_path}_"*)
        fi

        if [[ ${#split_files[@]} -gt 0 ]]; then
            
            if [[ -d "$full_dest" ]]; then
                full_dest="${full_dest}/$(basename "$src_path")"
            fi

            mkdir -p "$(dirname "$full_dest")"
           
            if bash -c "cat ${src_path}.* > \"$full_dest\" 2>/dev/null || cat ${src_path}_* > \"$full_dest\""; then
                LOG_END "Merge complete."
                return 0
            else
                ERROR_EXIT "Failed to merge split files."
                return 1
            fi
        fi
        
        ERROR_EXIT "Source not found: $src_path"
        return 1
    fi

   
    if [[ -d "$src_path" ]]; then
     
        mkdir -p "$full_dest"

        LOG_INFO "Merging directory: $log_label -> $partition/$dest_rel_path"
        
        
        if rsync -a --no-owner --no-group "${src_path}/" "$full_dest/"; then
            LOG_END "Directory merged."
            return 0
        else
            ERROR_EXIT "Directory merge failed."
            return 1
        fi
    fi

   
    if [[ -f "$src_path" ]]; then
        
        if [[ -d "$full_dest" ]]; then
            full_dest="${full_dest}/$(basename "$src_path")"
        fi

        if [[ -d "$full_dest" ]]; then
             ERROR_EXIT "Target conflict: Cannot overwrite directory '$full_dest' with file '$src_path'."
             return 1
        fi

        mkdir -p "$(dirname "$full_dest")"

        LOG_INFO "Copying: $log_label"
        if cp -f "$src_path" "$full_dest"; then
            LOG_END "File installed."
            return 0
        else
            ERROR_EXIT "File copy failed."
            return 1
        fi
    fi

    ERROR_EXIT "Unknown source type: $src_path"
    return 1
}
