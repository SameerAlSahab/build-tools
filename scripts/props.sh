##!/usr/bin/env bash
#
#  Copyright (c) 2025 Sameer Al Sahab
#  Licensed under the MIT License. See LICENSE file for details.
#
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#



# Usage: FF "TAG" "VALUE"
# FF "TAG" "" ->> means deletion of line
# Modifies /system/system/etc/floating_feature.xml for Samsung-specific features
FF() {
    local tag_name="$1"
    local tag_value="$2"
    local xml_file="${WORKSPACE}/system/system/etc/floating_feature.xml"

    if ! command -v xmlstarlet &> /dev/null; then
        ERROR_EXIT "xmlstarlet not found."
        return 1
    fi

    _SEC_FF_PREFIX tag_name

    if [[ -z "$tag_value" ]]; then
        if xmlstarlet sel -t -v "//${tag_name}" "$xml_file" &>/dev/null; then
            xmlstarlet ed -L -d "//${tag_name}" "$xml_file"
            LOG "Deleted floating feature: <${tag_name}>"
        fi
        return
    fi

    if [[ ! -f "$xml_file" ]]; then
        mkdir -p "$(dirname "$xml_file")"
        cat > "$xml_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<SecFloatingFeatureSet>
</SecFloatingFeatureSet>
EOF
        LOG_INFO "Created new floating_feature.xml"
    fi

    local current_value
    current_value=$(xmlstarlet sel -t -v "//${tag_name}" "$xml_file" 2>/dev/null || true)

    if [[ -n "$current_value" ]]; then
        if [[ "$current_value" != "$tag_value" ]]; then
            xmlstarlet ed -L -u "//${tag_name}" -v "$tag_value" "$xml_file"
            LOG "Updated : <${tag_name}>${tag_value}</${tag_name}>"
        else
            LOG_INFO "Unchanged : <${tag_name}> already set to ${tag_value}"
        fi
    else
        # Add new tag
        xmlstarlet ed -L -s '/SecFloatingFeatureSet' -t elem -n "$tag_name" -v "$tag_value" "$xml_file"
        LOG "Added : <${tag_name}>${tag_value}</${tag_name}>"
    fi
}


#
# Samsung floating feature have a common prefix at tag starting. [SEC_FLOATING_FEATURE_]
#
_SEC_FF_PREFIX() {
    local -n var_ref="$1"
    local REQUIRED_PREFIX="SEC_FLOATING_FEATURE_"
    if [[ "$var_ref" != ${REQUIRED_PREFIX}* ]]; then
        var_ref="${REQUIRED_PREFIX}${var_ref}"
    fi
}


#
# Usage: GET_FF_VAL [source] "TAG_NAME"
# Retrieves the value of a specified floating feature tag from the XML file.
#
GET_FF_VAL() {
    local source_firmware="main"
    local tag_name

    if [[ $# -eq 1 ]]; then
        tag_name="$1"
    elif [[ $# -eq 2 ]]; then
        source_firmware="$1"
        tag_name="$2"
    else
        LOG_WARN "Invalid number of arguments. Usage: GET_FF_VAL [source] 'tag_name'" >&2
        return 1
    fi

    local workspace_dir
    workspace_dir=$(GET_PARTITION_PATH "$source_firmware") || return 1

    local xml_file="${workspace_dir}/system/system/etc/floating_feature.xml"
    [[ ! -f "$xml_file" ]] && return 1

    _SEC_FF_PREFIX tag_name
    xmlstarlet sel -t -v "//${tag_name}" "$xml_file" 2>/dev/null || true
}



#
# Usage: _GET_PROP_PATHS <base_dir> <partition>
# Internal helper function to generate possible property file paths for a specific partition.
#
_GET_PROP_PATHS() {
    local base_dir="$1"
    local partition="$2"

    case "$partition" in
        "system")      echo "${base_dir}/system/system/build.prop" ;;
        "vendor")      echo "${base_dir}/vendor/build.prop" "${base_dir}/vendor/etc/build.prop" "${base_dir}/vendor/default.prop" ;;
        "product")     echo "${base_dir}/product/etc/build.prop" "${base_dir}/product/build.prop" ;;
        "system_ext")  echo "${base_dir}/system_ext/etc/build.prop" "${base_dir}/system/system/system_ext/etc/build.prop" ;;
        "odm")         echo "${base_dir}/odm/etc/build.prop" ;;
        "vendor_dlkm") echo "${base_dir}/vendor_dlkm/etc/build.prop" "${base_dir}/vendor/vendor_dlkm/etc/build.prop" ;;
        "odm_dlkm")    echo "${base_dir}/vendor/odm_dlkm/etc/build.prop" ;;
        "system_dlkm") echo "${base_dir}/system_dlkm/etc/build.prop" "${base_dir}/system/system/system_dlkm/etc/build.prop" ;;
    esac
}

#
# Usage: _RESOLVE_PROP_FILE <base_dir> <partition>
# Internal helper function to locate and return the high potential `build.prop` file in a specific partition.
#
_RESOLVE_PROP_FILE() {
    local base_dir="$1"
    local partition="$2"

    for file in $(_GET_PROP_PATHS "$base_dir" "$partition"); do
        if [[ -f "$file" ]]; then
            echo "$file"
            return 0
        fi
    done
    return 1
}

#
# Usage: _FIND_PROP_IN_PARTITION <base_dir> <partition> <prop_name>
# Internal helper function to locate and return the high potential `build.prop` file in a selected partition.
#
_FIND_PROP_IN_PARTITION() {
    local base_dir="$1"
    local partition="$2"
    local prop_name="$3"

    for file in $(_GET_PROP_PATHS "$base_dir" "$partition"); do
        if [[ -f "$file" ]] && grep -q -E "^${prop_name}=" "$file"; then
            echo "$file"
            return 0
        fi
    done
    return 1
}

#
# Adds, updates, or deletes entries in a `build.prop` file from a specific partition.
# Usage: BPROP <partition> <tag> <value>
# To delete a property: BPROP <partition> <tag> ""
#

BPROP() {
    local partition="$1"
    local tag="$2"
    local value="$3"


    local ASTRO_MARKER="# Added by AstroROM [utils/props.sh]"
    local END_MARKER="# end of file"
    local prop_file

    if [[ -z "$partition" || -z "$tag" ]]; then
        ERROR_EXIT "BPROP: Partition and Tag are required."
        return 1
    fi


    if ! prop_file=$(_FIND_PROP_IN_PARTITION "$WORKSPACE" "$partition" "$tag"); then

        prop_file=$(_RESOLVE_PROP_FILE "$WORKSPACE" "$partition")
    fi


    if [[ -z "$prop_file" || ! -f "$prop_file" ]]; then
        ERROR_EXIT "Cannot set property.No build.prop found for partition '$partition'."
        return 1
    fi


    local tmp_file
    tmp_file=$(mktemp)
    cp "$prop_file" "$tmp_file"


    if [[ -z "$value" ]]; then
        if grep -q "^${tag}=" "$tmp_file"; then
            sed -i "/^${tag}=/d" "$tmp_file"
            LOG "Deleted property from ${partition}: ${tag}"
        else
            LOG_INFO "Property not found in ${partition}: ${tag} (Nothing to delete)."
        fi


    elif grep -q "^${tag}=" "$tmp_file"; then

        sed -i "s|^${tag}=.*|${tag}=${value}|" "$tmp_file"
        LOG_INFO "Updated existing property in ${partition}: ${tag}=${value}"

    else

        local insert_content=""


        if ! grep -Fq "$ASTRO_MARKER" "$tmp_file"; then
            insert_content="${ASTRO_MARKER}\n"
        fi

        insert_content="${insert_content}${tag}=${value}"


        if grep -Fq "$END_MARKER" "$tmp_file"; then

            local end_footer
            end_footer=$(echo "$END_MARKER" | sed 's/[]\/$*.^[]/\\&/g')


            sed -i "/$end_footer/i $insert_content" "$tmp_file"
        else

            echo -e "$insert_content" >> "$tmp_file"
        fi

        LOG "Added new property to ${partition}: ${tag}=${value}"
    fi


if ! mv -f "$tmp_file" "$prop_file"; then
    rm -f "$tmp_file"
       ERROR_EXIT "Failed to write changes to $prop_file"
    return 1
fi

}

#
# Usage: DIFF_UPDATE_PROP <source_firmware> <src_partition> <tag> <dest_partition>
# Add property value from one firmware to another
# If the property already exists in workspace, it will be updated.
#
DIFF_UPDATE_PROP() {
    local source_firmware="$1"
    local src_partition="$2"
    local prop_tag="$3"
    local dest_partition="$4"

    local source_fs_dir
    source_fs_dir=$(GET_PARTITION_PATH "$source_firmware") || return 1

    local src_prop_path
    src_prop_path=$(_RESOLVE_PROP_FILE "$source_fs_dir" "$src_partition")

    if [[ -z "$src_prop_path" ]]; then
        LOG_WARN "Source prop file not found for partition '$src_partition' in '$source_firmware'."
        return 0
    fi

    local prop_value
    prop_value=$(grep -m 1 -E "^${prop_tag}=" "$src_prop_path" | cut -d '=' -f2- | tr -d '\r')

    if [[ -z "$prop_value" ]]; then
        LOG_WARN "Property '$prop_tag' not found in '$src_prop_path'."
        return 0
    fi

    BPROP "$dest_partition" "$prop_tag" "$prop_value"
}



#
# Usage: GET_PROP <partition> <prop_name>
# Retrieves the value of a specified property from the specified partition's `build.prop` file. Returns if not found.
#
GET_PROP() {
    local partition="$1"
    local prop_name="$2"
    local source_type="${3:-}"

    local prop_file
    if [[ -n "$source_type" ]]; then

        local workdir_path
        workdir_path=$(GET_FW_DIR "$source_type") || return 1
        prop_file=$(_RESOLVE_PROP_FILE "$workdir_path" "$partition") || return 1
    else

        prop_file=$(_RESOLVE_PROP_FILE "$WORKSPACE" "$partition")
        [[ -z "$prop_file" ]] && return 1
    fi

    # Check if the property exists in the file
    if ! grep -q "^${prop_name}=" "$prop_file"; then
        return 1
    fi

    grep "^${prop_name}=" "$prop_file" | cut -d'=' -f2- | tr -d '\r'
}
