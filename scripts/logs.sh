#!/bin/bash
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


LOG_WIDTH=80
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'


LOG_BEGIN() {
    echo "->$1"
}

LOG_END() {
    local description="$1"
    local status="${2:-}"

    echo
    if [[ -n "$status" ]]; then
        printf "${GREEN}[DONE]${NC} %s (%s)\n" "$description" "$status"
    else
        printf "${GREEN}[DONE]${NC} %s\n" "$description"
    fi
    echo
}


# Display error message and exit
ERROR_EXIT() {
    local msg="$1"
    local code="${2:-1}"

    echo
    printf "${RED}${BOLD}!!! PROCESS FAILED !!!${NC}\n"
    _PRINT_DIVIDER "="
  
    printf "${RED}>> %s${NC}\n" "$msg"
    printf "${RED}Exiting with code: %d${NC}\n" "$code"
    echo
    exit "$code"
}



# Check if a command exists
COMMAND_EXISTS() {
    command -v "$1" >/dev/null 2>&1
}


# Get current timestamp in HH:MM:SS format
_TIMESTAMP() {
    date '+%H:%M:%S'
}


_GET_DURATION() {
    local start=$1
    local end=$2
    local dt=$((end - start))
    local ds=$((dt % 60))
    local dm=$(((dt / 60) % 60))
    local dh=$((dt / 3600))
    
    if [ $dh -gt 0 ]; then
        printf "%02d:%02d:%02d" $dh $dm $ds
    else
        printf "%02d:%02d" $dm $ds
    fi
}


# Print a divider line with specified character
_PRINT_DIVIDER() {
    local char="${1:--}"
    printf "${GRAY}%*s${NC}\n" "$LOG_WIDTH" "" | tr ' ' "$char"
}



# Check if running in GitHub Actions environment
IS_GITHUB_ACTIONS() {
    [[ "${GITHUB_ACTIONS}" == "true" || "${CI}" == "true" ]]
}


LOG_INFO() {
    local msg="$1"
    echo -e "${GRAY}[$(_TIMESTAMP)]${NC} ${CYAN}[INFO]${NC} $msg"
}

LOG_WARN() {
    local msg="$1"
    echo -e "${GRAY}[$(_TIMESTAMP)]${NC} ${YELLOW}[WARN]${NC} $msg"
}


LOG() {
    local msg="$1"
    echo -e "$msg"
}


RUN_CMD() {
    local desc="$1"
    shift
    local cmd="$@"
    local start_ts
    local end_ts
    local duration
    local tmp_log
    local spin='-\|/'
    local i=0
    local pid

    start_ts=$(date +%s)
    tmp_log=$(mktemp)

    echo -ne "${GRAY}[$(_TIMESTAMP)]${NC} ${BLUE}[*]${NC}  $desc... "

    eval "$cmd" > "$tmp_log" 2>&1 &
    pid=$!

    if ! IS_GITHUB_ACTIONS; then
        tput civis 2>/dev/null
        while kill -0 "$pid" 2>/dev/null; do
            i=$(( (i+1) % 4 ))
            printf "\b${CYAN}%s${NC}" "${spin:$i:1}"
            sleep 0.1
        done
        tput cnorm 2>/dev/null
    else
        # In CI, just show a static indicator
        printf "${CYAN}[|]${NC}"
        wait "$pid"
    fi

    wait "$pid"
    local exit_code=$?
    end_ts=$(date +%s)
    duration=$(_GET_DURATION $start_ts $end_ts)

    if [ $exit_code -eq 0 ]; then
        printf "\b${GREEN}[OK]${NC} (${duration})\n"
        rm "$tmp_log"
    else
        printf "\b${RED}[FAIL]${NC}\n"

        echo
        printf "${RED}>> ERROR LOG OUTPUT:${NC}\n"
        _PRINT_DIVIDER "="
       
        tail -n 20 "$tmp_log" | while read -r line; do
             printf "${RED}| %s${NC}\n" "$line"
        done
        _PRINT_DIVIDER "="
        echo

        rm "$tmp_log"

        ERROR_EXIT "Build failed during: $desc" $exit_code
    fi
}

# Execute command silently
SILENT() {
    "$@" > /dev/null 2>&1
}


LOG_DIALOG() {
    local title="$1"
    local description="$2"

    echo
    _PRINT_DIVIDER "-"
    printf "${BLUE}|${NC} ${BOLD}${WHITE}%-$(($LOG_WIDTH - 4))s${NC} ${BLUE}|${NC}\n" "$title"

    if [[ -n "$description" ]]; then
        _PRINT_DIVIDER "-"
        
        printf "${BLUE}|${NC} ${DIM}%-$(($LOG_WIDTH - 4))s${NC} ${BLUE}|${NC}\n" "$description"
    fi
    _PRINT_DIVIDER "-"
    echo
}



CONFIRM_ACTION() {
    local prompt="$1"
    local default="${2:-false}"

    if IS_GITHUB_ACTIONS; then
        [[ "$default" == "true" ]] && return 0 || return 1
    fi

    local suffix="[y/N]"
    [[ "$default" == "true" ]] && suffix="[Y/n]"

    echo -ne "${MAGENTA}[?]${NC} $prompt $suffix: "
    read -r response
    [[ -z "$response" ]] && [[ "$default" == "true" ]] && return 0

    case "${response,,}" in
        y|yes) return 0 ;;
        *) return 1 ;;
    esac
}


_CHOICE() {
    local prompt="$1"; shift
    local options=("$@")
    local idx

    echo >&2
    printf "${BOLD}${WHITE}%s${NC}\n" "$prompt" >&2
    for i in "${!options[@]}"; do
        printf "  ${CYAN}[%d]${NC} %s\n" $((i+1)) "${options[$i]}" >&2
    done

    while true; do
        printf "${GREEN}>${NC} Select (1-${#options[@]}): " >&2
        read -r idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le ${#options[@]} ]; then
            echo "$idx"
            return 0
        fi
    done
}


_UPDATE_LOG() {
    local message="$1"
    local end_flag="$2"

    printf "\r\e[2K${WHITE}%b${NC}" "$message"

    if [[ "$end_flag" == "DONE" || "$end_flag" == "END" ]]; then
        echo ""
    fi
}
