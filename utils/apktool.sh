#!/bin/bash
# -----------------------------------------------------------------------------
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
# -----------------------------------------------------------------------------

#Special Thanks to @BlackMesa123 for help and hints on github for fix dex version issues

###Sources

#https://github.com/iBotPeaches/Apktool/issues/3775

#https://github.com/iBotPeaches/Apktool/pull/3879

#https://github.com/SameerAlSahab/smali_patch/blob/main/smali_patch.py for .smalipatch beside of singular .patch files

#https://github.com/salvogiangri/UN1CA/blob/fifteen/scripts/apktool.sh

# Use 'nproc' to dynamically get the number of available cores for APKTool's -j flag (jobs)
usable_threads=$(nproc)

APPLY_PATCH() {
    local work_dir="$1"     # Path to the decoded directory (e.g., .../framework.jar_decoded)
    local patch_file="$2"   # Path to the specific .patch file (e.g., .../enable_applock.patch)

    [[ -z "$work_dir" ]] && ERROR_EXIT "No target directory specified for patch"
    [[ -z "$patch_file" ]] && ERROR_EXIT "No patch file specified"

    [[ ! -d "$work_dir" ]] && ERROR_EXIT "Decoded directory not found for patching: $work_dir. Run decode first."

    if ! command -v patch &> /dev/null; then
        ERROR_EXIT "The 'patch' utility is not installed. Please install it to use this function."
    fi

    local original_dir="$(pwd)"

    LOG_INFO "Applying $(basename "$patch_file") inside $work_dir"

    (
        # 1. Change to the decoded directory, where the patch targets reside.
        cd "$work_dir" || exit 1

        # 2. Dry run first
        local dry_run_output
        dry_run_output=$(patch -p1 --dry-run < "$patch_file" 2>&1)
        if [[ $? -ne 0 ]]; then
            LOG_ERROR "Dry run failed for patch: $(basename "$patch_file")"
            echo "$dry_run_output"
            # Return 0 here to fail gracefully inside the subshell,
            # allowing the main script to handle the exit code.
            exit 1
        fi

        # 3. Apply patch
        if patch -p1 < "$patch_file"; then
            LOG_SUCCESS "Applied $(basename "$patch_file") successfully"
        else
            LOG_ERROR "Failed to apply patch: $(basename "$patch_file")"
            exit 1
        fi
    )

    # Check the exit status of the subshell (which ran the patch commands)
    if [[ $? -ne 0 ]]; then
        return 1 # Patch failed
    fi

    # Return to original directory
    cd "$original_dir" || LOG_WARNING "Could not return to original directory"

    return 0 # Patch succeeded
}

APPLY_SMALI_PATCH() {
    local file="$1"
    shift

    [[ -z "$file" ]] && ERROR_EXIT "No file specified for patch"

    local work_dir="$file"
    local patch_file="$1" # The second argument is the path to the individual patch file

    [[ ! -d "$work_dir" ]] && ERROR_EXIT "Decoded directory not found for smali patch: $work_dir. Run decode first."



    local patch_dir="$(dirname "$patch_file")"


    local smali_bin="${BIN}/smali_patcher"
    [[ ! -x "$smali_bin" ]] && smali_bin="${ASTROROM}/bin/smalipatcher"
    [[ ! -x "$smali_bin" ]] && ERROR_EXIT "Smali patcher binary not found or not executable"

    LOG_INFO "Processing $(basename "$patch_file") on $work_dir"

    # Execute only the single patch file
    if "$smali_bin" "$work_dir" "$patch_file" ; then #more args --non-strict
        LOG_SUCCESS "Successfully applied patch: $(basename "$patch_file")"
        return 0
    else
        LOG_ERROR "Failed to apply patch: $(basename "$patch_file")"
        return 1
    fi
}

INSTALL_FRAMEWORK() {
    local framework_res="${WORKSPACE}/system/system/framework/framework-res.apk"
    local build_prop="${WORKSPACE}/system/system/build.prop"

    if [[ ! -f "$framework_res" ]]; then
        ERROR_EXIT "framework-res.apk not found"
    fi

    if [[ ! -f "$build_prop" ]]; then
        ERROR_EXIT "build.prop not found"
    fi

    # Use fixed framework tag instead of incremental version
    local framework_tag="framework-res"

    if [[ ! -f "${FRAMEWORK_DIR}/1-${framework_tag}.apk" ]]; then
        LOG_INFO "Installing framework-res with tag: $framework_tag"
        java -jar "$BIN/apktool/apktool.jar" if -p "$FRAMEWORK_DIR" -t "$framework_tag" "$framework_res" || \
            ERROR_EXIT "Failed to install framework-res"
    fi
}

DEX_2_API() {
    local DEX_FILE="$1"
    local DEX_VERSION

    # Read the 4-byte DEX magic version string (e.g., "035\0") from offset 4
    DEX_VERSION=$(xxd -s 4 -l 4 -p "$DEX_FILE")

    local API
    case "$DEX_VERSION" in
        "30333500") # "035"
            API="23"
            ;;
        "30333700") # "037"
            API="25"
            ;;
        "30333800") # "038"
            API="27"
            ;;
        "30333900") # "039"
            API="29"
            ;;
        "30343000") # "040"
            API="34"
            ;;
        "30343100") # "041"
            API="35"
            ;;
        *)

            LOG_WARN "Unknown DEX format version ($DEX_VERSION) found. Defaulting to API 31."
            API="35"
            ;;
    esac

    echo "$API"
}
DEX_2_API() {
    local DEX_FILE="$1"
    local DEX_VERSION

    # Read the 4-byte DEX magic version string (e.g., "035\0") from offset 4
    DEX_VERSION=$(xxd -s 4 -l 4 -p "$DEX_FILE")

    local API
    case "$DEX_VERSION" in
        "30333500") # "035"
            API="23"
            ;;
        "30333700") # "037"
            API="25"
            ;;
        "30333800") # "038"
            API="27"
            ;;
        "30333900") # "039"
            API="29"
            ;;
        "30343000") # "040"
            API="34"
            ;;
        "30343100") # "041"
            API="35"
            ;;
        *)
            LOG_WARN "Unknown DEX format version ($DEX_VERSION) found. Defaulting to API 35."
            API="35"
            ;;
    esac

    echo "$API"
}

DECOMP_APK() {
    local file="$1"
    [[ -z "$file" ]] && ERROR_EXIT "No file specified for decode"

    [[ "$file" != /* ]] && file="${WORKSPACE}/$file"
    [[ ! -f "$file" ]] && ERROR_EXIT "File not found: $file"

    local name="$(basename "$file")"
    local base="${name%.*}"
    local ext="${name##*.}"
    local dir="$(dirname "$file")"

    local work_dir="${dir}/${name}_decoded"


    if [[ -d "$work_dir" ]]; then
        LOG_WARN "Removing existing decode directory: $work_dir"
        rm -rf "$work_dir"
    fi


    mkdir -p "$work_dir" || ERROR_EXIT "Failed to create directory: $work_dir"


    local original_dir="${WORKSPACE}/decode/${base}"

    LOG_INFO "Decoding $name to target directory: $work_dir..."



    INSTALL_FRAMEWORK

    local API=""
    local framework_tag="framework-res"

    # --- START JAR HANDLING WITH CONDITIONAL V041 FIX ---
    if [[ "$ext" == "jar" ]]; then
        LOG_INFO "Detected JAR file. Determining API level..."

        local temp_dex_file
        temp_dex_file="$(mktemp)"
        local jar_dex_exists=false
        local dex_file_to_check=""

        # Finds the available DEX file (e.g., classes.dex, then classes2.dex)
        if command -v 7z &>/dev/null; then
            dex_file_to_check=$(7z l "$file" | grep -E -o 'classes[0-9]*\.dex' | sort | head -n 1)
        else
            dex_file_to_check=$(unzip -l "$file" | grep -E 'classes[0-9]*\.dex' | awk '{print $NF}' | sed 's#.*/##' | sort | head -n 1)
        fi

        if [[ -n "$dex_file_to_check" ]]; then
            LOG_INFO "Using $dex_file_to_check for API level check..."
            if command -v 7z &>/dev/null; then
                7z e -y -so "$file" "$dex_file_to_check" >"$temp_dex_file" 2>/dev/null
                [[ -s "$temp_dex_file" ]] && jar_dex_exists=true
            else
                unzip -p "$file" "$dex_file_to_check" >"$temp_dex_file" 2>/dev/null
                [[ -s "$temp_dex_file" ]] && jar_dex_exists=true
            fi
        fi

        if [[ "$jar_dex_exists" == true && -s "$temp_dex_file" ]]; then
            API=$(DEX_2_API "$temp_dex_file")
            LOG_INFO "Determined API level from JAR DEX: $API"
        else
            API="35"
            LOG_WARN "No DEX found in JAR or extraction failed. Defaulting API to $API."
        fi

        # Get the raw DEX magic version for the conditional check
        local raw_dex_version=""
        if [[ -s "$temp_dex_file" ]]; then
            raw_dex_version=$(xxd -s 4 -l 4 -p "$temp_dex_file")
            rm -f "$temp_dex_file"
        fi

        echo "$API" > "${work_dir}/dex_api_level"


        if [[ "$API" == "35" ]] && [[ "$name" == "services.jar" ]] && [[ "$raw_dex_version" == "30343100" ]]; then
            LOG_WARN "‼️ Detected services.jar (DEX v041). Using container extraction workaround."

            # 1. Use APKTool with -s flag (skip smali) to extract resources and original DEX files
            java -jar "${BIN}/apktool/apktool.jar" d -api "$API" -f -j "$usable_threads" -o "$work_dir" -p "$FRAMEWORK_DIR" -t "$framework_tag" -s "$file" || \
                ERROR_EXIT "Failed to decode $name resources."

            LOG_INFO "Disassembling DEX containers..."

            local PART=1
            local MAX_PARTS=4 # Safety limit

            while [[ $PART -le $MAX_PARTS ]]; do
                local INPUT_PATH
                local SMALI_OUT

                # Use base name for Part 1, use /X for subsequent parts
                if [[ $PART -eq 1 ]]; then
                    INPUT_PATH="${file}/classes.dex"
                    SMALI_OUT="smali"
                else
                    INPUT_PATH="${file}/classes.dex/${PART}"
                    SMALI_OUT="smali_classes${PART}"
                fi

                LOG_INFO "Attempting to disassemble container part: ${INPUT_PATH} -> ${SMALI_OUT}"

                # Run baksmali using the direct container path
                java -jar "${BIN}/smali/baksmali.jar" d -a "$API" -j "$usable_threads" \
                    --ac false --di false -l -o "${work_dir}/${SMALI_OUT}" "$INPUT_PATH"

                if [[ $? -ne 0 ]]; then
                    LOG_INFO "No more containers found or extraction failed on part ${PART}."

                    if [[ $PART -eq 1 ]]; then
                        ERROR_EXIT "Failed to extract main classes.dex using container method. Aborting."
                    fi

                    if [[ -d "${work_dir}/${SMALI_OUT}" ]] && ! find "${work_dir}/${SMALI_OUT}" -mindepth 1 -print -quit 2>/dev/null; then
                        rm -rf "${work_dir}/${SMALI_OUT}"
                    fi
                    break
                fi

                LOG_SUCCESS "Successfully disassembled part ${PART}."
                PART=$((PART + 1))
            done

            # Clean up the original DEX files extracted by apktool -s
            LOG_INFO "Cleaning up original DEX files..."
            rm -f "${work_dir}/classes"*.dex

            # Extract resources (same as original JAR logic)
            if unzip -l "$file" | grep -q "debian.mime.types"; then
                LOG_INFO "Extracting Android 14+/15 resources from JAR..."
                mkdir -p "${work_dir}/__extra_res__"
                unzip -q "$file" "res/*" -d "${work_dir}/__extra_res__" || \
                    LOG_WARN "Failed to extract resources from JAR"
            fi

            LOG_SUCCESS "Container disassembly complete. Total parts: $((PART - 1))"
            echo "$work_dir"
            return

        else

            LOG_INFO "Using standard APKTool decode for JAR (API: $API)."
            java -jar "${BIN}/apktool/apktool.jar" d -api "$API" -f -j "$usable_threads" -o "$work_dir" -p "$FRAMEWORK_DIR" -t "$framework_tag" -s "$file" || \
                ERROR_EXIT "Failed to decode $name"

        fi

    else

        local decode_flags=("-f" "-j" "$usable_threads" "-o" "$work_dir" "-p" "$FRAMEWORK_DIR" "-t" "$framework_tag")

        # Check if we should decode resources (i.e., NOT use -r).
        if [[ "$base" == "SecSettings" || "$base" == "SystemUI" ]]; then
            LOG_INFO "Target $name is SecSettings or SystemUI. Decoding resources fully."
        else
            LOG_INFO "Target $name is a regular APK. Skipping resource decoding (-r)."
            decode_flags+=("-r") # Add -r to the array for all other files
        fi

        # Always skip Smali decoding (-s flag)
        decode_flags+=("-s")

        # Execute the command.
        java -jar "${BIN}/apktool/apktool.jar" d "${decode_flags[@]}" "$file" || \
            ERROR_EXIT "Failed to decode $name"

    fi

    if [[ "$ext" == "apk" || ("$ext" == "jar" && "$name" != "services.jar") ]]; then # Exclude special JAR if it ran above
        LOG_INFO "Disassembling DEX files..."
        local first_dex_api=""

        while IFS= read -r dex_file; do
            local smali_out="smali"
            local dex_name="$(basename "$dex_file")"

            if [[ "$dex_name" != "classes.dex" ]]; then
                smali_out="smali_${dex_name%.dex}"
            fi

            # Get API level from DEX file
            local dex_api=$(DEX_2_API "$dex_file")

            # Save the API level from the first DEX *only if* we didn't
            if [[ -z "$first_dex_api" ]]; then
                first_dex_api="$dex_api"
                if [[ ! -f "${work_dir}/dex_api_level" ]]; then
                    echo "$dex_api" > "${work_dir}/dex_api_level"
                fi
            fi

            # Disassemble with baksmali
            java -jar "${BIN}/smali/baksmali.jar" d -a "$dex_api" --ac false --di false \
                -j "$usable_threads" -l -o "${work_dir}/${smali_out}" --sl "$dex_file" || \
                ERROR_EXIT "Failed to disassemble $dex_file"

            rm -f "$dex_file"
        done < <(find "$work_dir" -maxdepth 1 -name "*.dex")
    fi

    if [[ "$ext" == "jar" ]] && [[ "$name" != "services.jar" ]]; then
        if unzip -l "$file" | grep -q "debian.mime.types"; then
            LOG_INFO "Extracting Android 14+/15 resources from JAR..."
            mkdir -p "${work_dir}/__extra_res__"
            unzip -q "$file" "res/*" -d "${work_dir}/__extra_res__" || \
                LOG_WARN "Failed to extract resources from JAR"
        fi
    fi

    LOG_SUCCESS "Decoded to $work_dir"
    echo "$work_dir"
}

RECOMP_APK() {
    local file="$1"
    [[ -z "$file" ]] && ERROR_EXIT "No file specified for encode"

    # Resolve full file path
    [[ "$file" != /* ]] && file="${WORKSPACE}/$file"
    [[ ! -f "$file" ]] && ERROR_EXIT "File not found: $file"

    local name="$(basename "$file")"
    local ext="${name##*.}"
    local dir="$(dirname "$file")"


    local work_dir="${dir}/${name}_decoded"

    LOG_INFO "Attempting to build from directory: $work_dir"
    [[ -d "$work_dir" ]] || ERROR_EXIT "Decoded directory not found for $name. Run decode first."

    LOG_INFO "Building $name..."

    INSTALL_FRAMEWORK


    local api_level="35"
    if [[ -f "${work_dir}/dex_api_level" ]]; then
        api_level=$(cat "${work_dir}/dex_api_level")
        LOG_INFO "Using API level from file: $api_level"
    else
        LOG_WARN "No API level file found. Defaulting to $api_level."
    fi

    mkdir -p "${work_dir}/dist"


    local copy_flag=""
    local signing_enabled=false


    if [[ "${DO_SIGN_APK,,}" == "true" ]] || [[ "$DO_SIGN_APK" == "1" ]] || [[ "${DO_SIGN_APK,,}" == "yes" ]]; then
        signing_enabled=true
    fi

    # Always use -c for both APK and JAR to preserve META-INF structure
    if [[ "$ext" == "jar" ]] || [[ "$ext" == "apk" ]]; then
        copy_flag="-c"
        LOG_INFO "Building with -c flag to preserve original file structure (META-INF, etc.)."
    fi


    java -jar "${BIN}/apktool/apktool.jar" b -api "$api_level" "$copy_flag" \
        -j "$usable_threads" -p "$FRAMEWORK_DIR" \
        -o "${work_dir}/dist/${name}" "$work_dir" || \
        ERROR_EXIT "Failed to build $name"


    if [[ "$ext" == "apk" ]] && [[ "$signing_enabled" == true ]]; then

        [[ ! -f "$CERT_PEM" ]] && ERROR_EXIT "Signing failed: PEM file not found at $CERT_PEM"
        [[ ! -f "$CERT_PK8" ]] && ERROR_EXIT "Signing failed: PK8 file not found at $CERT_PK8"

        LOG_INFO "Signing APK: ${name} with ${CERT_PEM} and ${CERT_PK8}..."


        local unsigned_file="${work_dir}/dist/${name}.unsigned"
        mv "${work_dir}/dist/${name}" "$unsigned_file"

        # Sign the APK
        java -jar "${BIN}/signapk/signapk.jar" \
            "$CERT_PEM" "$CERT_PK8" \
            "$unsigned_file" "${work_dir}/dist/${name}" || \
            ERROR_EXIT "Failed to sign APK: $name"

        # Remove the temporary unsigned file
        rm -f "$unsigned_file"

        LOG_SUCCESS "APK signed successfully."
    fi

    # Reintegrate Android 14+ resources if needed for JAR files
    if [[ "$ext" == "jar" ]] && [[ -d "${work_dir}/__extra_res__" ]]; then
        LOG_INFO "Reintegrating Android 14+ resources..."
        (cd "${work_dir}/__extra_res__" && zip -qr "${work_dir}/dist/${name}" .) || {
            ERROR_EXIT "Failed to add Android 14+ resources to JAR"
        }
    fi

    # Zipalign APK files
    if [[ "$ext" == "apk" ]]; then
        LOG_INFO "Zipaligning $name..."
        local temp_file="${work_dir}/dist/temp.apk"


        zipalign -f 4 "${work_dir}/dist/${name}" "$temp_file" || \
            ERROR_EXIT "Zipalign failed for $name. The resulting file may be corrupted."

        if [[ ! -f "$temp_file" ]]; then
            ERROR_EXIT "Zipalign created a broken or non-existent file."
        fi

        mv -f "$temp_file" "${work_dir}/dist/${name}" || ERROR_EXIT "Failed to move zipaligned file."
        LOG_SUCCESS "APK zipaligned successfully."
    fi

    LOG_INFO "Replacing original file with the newly built file: ${file}"
    mv -f "${work_dir}/dist/${name}" "$file" || ERROR_EXIT "Failed to replace $file"

    LOG_INFO "Cleaning up temporary decoded directory: $work_dir"
    rm -rf "$work_dir"

    LOG_SUCCESS "Built $name successfully!"
}



_RESOLVE_APK_JAR_DIR() {
    local file_name="$1"
    local full_path

    # JAR files (framework)
    if [[ "$file_name" == *.jar ]]; then
        local target_dir
        target_dir=$(RESOLVE_TARGET_DIR "system" "$WORKSPACE")
        full_path="${target_dir}/framework/${file_name}"
        if [[ -f "$full_path" ]]; then
            LOG_INFO "Located JAR file: $full_path" >&2
            echo "$full_path"
            return 0
        fi
    fi

    # APK files (system apps)
    if [[ "$file_name" == *.apk ]]; then
        local partition_list=("system" "system_ext" "product" )
        for part in "${partition_list[@]}"; do
            local part_dir
            part_dir=$(RESOLVE_TARGET_DIR "$part" "$WORKSPACE")

            # Check in app/subdirectory/
            for app_subdir in "${part_dir}/app/"*/; do
                local app_path="${app_subdir}${file_name}"
                if [[ -f "$app_path" ]]; then
                    LOG_INFO "Located APK file in ${part}/app/$(basename "$app_subdir")/: $app_path" >&2
                    echo "$app_path"
                    return 0
                fi
            done

            # Check in priv-app/subdirectory/
            for priv_app_subdir in "${part_dir}/priv-app/"*/; do
                local priv_app_path="${priv_app_subdir}${file_name}"
                if [[ -f "$priv_app_path" ]]; then
                    LOG_INFO "Located APK file in ${part}/priv-app/$(basename "$priv_app_subdir")/: $priv_app_path" >&2
                    echo "$priv_app_path"
                    return 0
                fi
            done
        done
    fi

    LOG_WARN "Could not locate file in workspace for patching: ${file_name}. Skipping." >&2
    return 1
}

_PROCESS_PATCH_TARGET() {
    local base_name="$1"
    [[ -z "$base_name" ]] && { LOG_ERROR "Patch target name is required."; return 1; }

    local target_file
    target_file=$(_RESOLVE_APK_JAR_DIR "$base_name")
    [[ $? -ne 0 || -z "$target_file" ]] && return 0

    local relative_target_file="${target_file#$WORKSPACE/}"
    local dir_path="$(dirname "$target_file")"
    local decoded_dir="${dir_path}/${base_name}_decoded" # <-- This is the directory we need

    local patch_dirs=()


    while IFS= read -r -d '' dir; do
        patch_dirs+=("$dir")
    done < <(find "${ASTROROM}/objectives/$device/" -type d -name "$base_name" -print0 2>/dev/null)


    local project_dir="${PROJECT_DIR}/patches/${base_name}"
    [[ -d "$project_dir" ]] && patch_dirs+=("$project_dir")

    IFS=$'\n' patch_dirs=($(sort -u <<<"${patch_dirs[*]}")); unset IFS
    [[ ${#patch_dirs[@]} -eq 0 ]] && { LOG_INFO "No patches found for $base_name. Skipping."; return 0; }

    local patches_exist=0

    for dir in "${patch_dirs[@]}"; do
        if compgen -G "${dir}/*.patch" > /dev/null || compgen -G "${dir}/*.smalipatch" > /dev/null; then
            patches_exist=1
            break
        fi
    done

    if [[ "$patches_exist" -eq 0 ]]; then
        LOG_INFO "Patch directories found for $base_name, but no patch files (.patch/.smalipatch) inside. Skipping decode/patch."
        return 0
    fi


    if [[ ! -d "$decoded_dir" ]]; then
        LOG_INFO "Decoded directory not found. Decoding $base_name..."

        DECOMP_APK "$relative_target_file" || { LOG_ERROR "Failed to decode $base_name. Aborting patch."; return 1; }
    else
        LOG_INFO "Decoded directory '$decoded_dir' already exists. Skipping decode and patching in place."
    fi

    local patch_status=0

for dir in "${patch_dirs[@]}"; do
    LOG_INFO "Applying patches from directory: $dir"

    local patch_files=()


    while IFS= read -r -d '' patch_file; do
        patch_files+=("$patch_file")
    done < <(find "$dir" -maxdepth 1 \( -name "*.patch" -o -name "*.smalipatch" \) -type f -print0 | sort -z)


    for patch_file in "${patch_files[@]}"; do
        _PROCESS_SINGLE_PATCH "$patch_file" "$decoded_dir"
        local exit_code=$?

        # Check the result of _PROCESS_SINGLE_PATCH
        if [[ $exit_code -eq 1 ]]; then

            patch_status=1
        elif [[ $exit_code -eq 0 ]]; then

            :
        elif [[ $exit_code -eq 2 ]]; then

            :
        fi
    done


    LOG_INFO "Checking for direct file overlays and scripts in $dir"



    # Merge res
    if [[ -d "${dir}/res" ]]; then
        LOG_INFO "Merging res directory..."

        rsync -a "${dir}/res/" "${decoded_dir}/res/" || {
            LOG_ERROR "Failed to merge res from $dir"
            patch_status=1
        }
    fi

    # Merge smali
    if [[ -d "${dir}/smali" ]]; then
        LOG_INFO "Merging smali directory..."
        rsync -a "${dir}/smali/" "${decoded_dir}/smali/" || {
            LOG_ERROR "Failed to merge smali from $dir"
            patch_status=1
        }
    fi

    # Merge smali_classes* (e.g., smali_classes2, smali_classes3, etc.)
    if compgen -G "${dir}/smali_classes*" > /dev/null; then
        for smali_src_dir in "${dir}"/smali_classes*; do
            if [[ -d "$smali_src_dir" ]]; then
                local smali_base_name=$(basename "$smali_src_dir")
                LOG_INFO "Merging $smali_base_name directory..."
                # Ensure the target directory exists
                mkdir -p "${decoded_dir}/${smali_base_name}"
                rsync -a "$smali_src_dir/" "${decoded_dir}/${smali_base_name}/" || {
                    LOG_ERROR "Failed to merge $smali_base_name from $dir"
                    patch_status=1
                }
            fi
        done
    fi


    if compgen -G "${dir}/*.sh" > /dev/null; then
        for script_file in "${dir}"/*.sh; do

            if [[ -f "$script_file" ]]; then
                LOG_INFO "Executing custom script: $script_file (within $decoded_dir)"

                (
                    cd "$decoded_dir" || { LOG_ERROR "Could not cd to $decoded_dir"; exit 1; }

                    bash "$script_file"
                ) || {
                    LOG_ERROR "Custom script $script_file failed"
                    patch_status=1
                }
            fi
        done
    fi


done


    if [[ "$patch_status" -ne 0 ]]; then
        LOG_ERROR "One or more patches failed for $base_name. Cleaning up decoded directory: $decoded_dir"
        rm -rf "$decoded_dir"
        return 1
    fi

    LOG_SUCCESS "Patch workflow for $base_name completed successfully. Ready for final recompilation."

    return 0
}

_PROCESS_SINGLE_PATCH() {
    local patch_file="$1"
    local decoded_dir="$2"

    local current_hash
    current_hash=$(_GET_MD5_HASH "$patch_file")
    if [[ -z "$current_hash" ]]; then
        LOG_WARN "Could not find or hash patch file: $(basename "$patch_file"). Skipping."
        return 2
    fi

    local cached_hash="${SCRIPT_CACHE[$patch_file]:-}"


    if [[ -n "$cached_hash" ]] && [[ "$cached_hash" == "$current_hash" ]]; then
        LOG_INFO "Skipping patch: $(basename "$patch_file") (Unchanged)"
        return 2
    fi

    local patch_type
    local patch_func_name

    if [[ "$patch_file" == *.smalipatch ]]; then
        patch_type="smalipatch"
        patch_func_name="APPLY_SMALI_PATCH"
    elif [[ "$patch_file" == *.patch ]]; then
        patch_type="patch"
        patch_func_name="APPLY_PATCH"
    else
        LOG_WARN "Unknown patch type for file: $(basename "$patch_file"). Skipping."
        return 2
    fi


    if [[ -z "$cached_hash" ]]; then
        LOG_START "Applying $patch_type: $(basename "$patch_file")"
    else
        LOG_START "Re-applying $patch_type: $(basename "$patch_file") (Change detected)"
    fi


    if ! "$patch_func_name" "$decoded_dir" "$patch_file"; then
        LOG_ERROR "Patch failed: $(basename "$patch_file"). Not updating cache. Will retry."
        return 1
    fi


    UPDATE_MARKER "$patch_file" "$current_hash"
    LOG_END "Applied successfully: $(basename "$patch_file")"
    return 0
}

RECOMP_ALL_DECODED() {
    local recompile_list=()
    local result_status=0


    while IFS= read -r -d '' dir; do

        local decoded_name="$(basename "$dir")"
        local original_name="${decoded_name%_decoded}"


        local original_dir="$(dirname "$dir")"
        local original_file="${original_dir}/${original_name}"


        local relative_path="${original_file#$WORKSPACE/}"


        if [[ -f "$original_file" ]]; then
            recompile_list+=("$relative_path")
        else
            LOG_WARN "Original file not found for decoded directory $decoded_name at $original_file. Cleaning up stale directory."
            rm -rf "$dir"
        fi
    done < <(find "$WORKSPACE" -type d -name "*_decoded" -print0 2>/dev/null)

    if [[ ${#recompile_list[@]} -eq 0 ]]; then
        LOG_WARN "No decoded directories found for final recompilation."
        return 0
    fi

    LOG_INFO "Found ${#recompile_list[@]} files for final recompilation."

    for relative_path in "${recompile_list[@]}"; do
        LOG_INFO "Recompiling: $relative_path"


        RECOMP_APK "$relative_path" || {
            LOG_ERROR "Final recompilation failed for $relative_path."
            result_status=1
        }
    done

    return $result_status
}



AUTOPATCH_ALL() {
local target_names=()


    LOAD_MARKERS



    while IFS= read -r -d '' dir; do
        local name="$(basename "$dir")"

        if [[ -d "$dir" && ("$name" == *.apk || "$name" == *.jar) ]]; then
            target_names+=("$name")
            LOG_INFO "Found objective patch directory: $name"
        fi
    done < <(find "${ASTROROM}/objectives/$device/" -type d \( -name "*.apk" -o -name "*.jar" \) -print0 2>/dev/null)



    while IFS= read -r -d '' dir; do
        local name="$(basename "$dir")"
        if [[ -d "$dir" && ("$name" == *.apk || "$name" == *.jar) ]]; then
            target_names+=("$name")
            LOG_INFO "Found project patch directory: $name"
        fi
    done < <(find "${PROJECT_DIR}/patches/" -maxdepth 1 -mindepth 1 -type d \( -name "*.apk" -o -name "*.jar" \) -print0 2>/dev/null)


    local unique_targets=()
    declare -A seen_targets

    for name in "${target_names[@]}"; do
        if [[ -z "${seen_targets[$name]}" ]]; then
            unique_targets+=("$name")
            seen_targets["$name"]=1
        fi
    done

    if [[ ${#unique_targets[@]} -eq 0 ]]; then
        LOG_WARN "No APK or JAR patches found , skipping patching..."

        RECOMP_ALL_DECODED && return 0 || return 1
    fi

    LOG_INFO "Found ${#unique_targets[@]}  patch targets: ${unique_targets[*]}"

    local patch_success=0
    local patch_fail=0


    for target in "${unique_targets[@]}"; do
        LOG_INFO "Starting patch process for: $target"
        if _PROCESS_PATCH_TARGET "$target"; then
            patch_success=$((patch_success + 1))
        else
            patch_fail=$((patch_fail + 1))
        fi
    done

    LOG_INFO "Patching Summary: $patch_success Succeeded, $patch_fail Failed."


    if [[ "$patch_fail" -gt "$patch_success" ]]; then
        LOG_ERROR "Too many patches failed. Aborting final recompilation."
        return 1
    fi


    LOG_INFO "Starting recompilation of all *\_decoded directories in the workspace."
    if RECOMP_ALL_DECODED; then
        LOG_SUCCESS "Patching completed successfully."
        return 0
    else
        LOG_ERROR "Final recompilation failed for one or more files."
        return 1
    fi
}
