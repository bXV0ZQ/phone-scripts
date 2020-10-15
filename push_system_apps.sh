#!/usr/bin/bash

SCRIPT_NAME=$(basename $0)

#
# CONFIGURATION
#

# Default values
declare -r DEF_SRC_FOLDER="./files"

# Configuration
declare -r PRIV_APP_FOLDER="/system/priv-app"
declare -r PERMISSIONS_FOLDER="/system/etc/permissions"

#
# UTILS
#

RED="\\033[1;31m"
GREEN="\\033[1;32m"
YELLOW="\\033[1;33m"
BLUE="\\033[1;34m"
MAGENTA="\\033[1;35m"
CYAN="\\033[1;36m"
BOLD="\\033[1m"
END="\\033[1;00m"
FATAL="\\033[1;37;41m" # WHITE on RED

print_info () {
    echo -e "${GREEN} [INFO]${END} $@"
}

print_error () {
    echo -e "${RED} [ERROR]${END} $@"
}

print_warn () {
    echo -e "${YELLOW} [WARN]${END} $@"
}

usage () {
    local USAGE

# \n is required to preserve whitespaces for the first line (and adding a new line before printing the usage message is a good deal)
    read -r -d '' USAGE << EOM
\n    Usage: ${SCRIPT_NAME} [-s <source>]
    
    Push ${YELLOW}system apps${END} to the mobile through ADB.
    These apps are usually wiped when applying an OTA update so they need to be reinstalled regularly.

    Options:
        -s|--source ${BOLD}<source>${END}
            The path to apk and permissions files source folder (default: '${DEF_SRC_FOLDER}')
            Limited to alphanumeric, '.', '-', '_', ' ' and '/' characters
            Must exist and be a folder.
    
    Others:
        -h|--help: print this help message

EOM
    echo -e "${USAGE}"
}

#
# RETRIEVE INPUT
#

# Need help?
case "$1" in
    "-h"|"--help") usage && exit 0;;
esac

# Look for options
while [[ -n "$1" ]]; do
    case "$1" in
        "-s"|"--source")
            if [[ $# -ge 2 ]]; then
                ARG_SRC_FOLDER="$2"
                shift 2
            else
                print_error "Missing apk source folder after '$1'" && usage && exit 1
            fi
            ;;
        "-h"|"--help") usage && exit 0;;
        *) print_error "Unknown command '$1'" && usage && exit 1;;
    esac
done

# Prepare options
SRC_FOLDER=${ARG_SRC_FOLDER:-${DEF_SRC_FOLDER}}

#
# INPUT VALIDATION
#

# Validation SRC_DIR
[[ "${SRC_FOLDER}" =~ [^a-zA-Z0-9\ /_.-]+ ]] && print_error "Invalid source folder (bad characters): '${SRC_FOLDER}'" && usage && exit 1
[[ ! -d "${SRC_FOLDER}" ]] && print_error "Source folder doesn't exist or is not a folder" && usage && exit 1

#
# FUNCTIONS
#

# Install a system app from its apk folder name, apk file name and permission file name
install_system_app () {
    local apk_folder_name="${1}"
    local apk_file_name="${2}"
    local perm_file_name="${3}"

    [[ "${apk_folder_name}" =~ [^a-zA-Z0-9_.-]+ ]] && return 10
    [[ "${apk_file_name}" =~ [^a-zA-Z0-9_.-]+ ]] && return 20
    [[ "${perm_file_name}" =~ [^a-zA-Z0-9_.-]+ ]] && return 30

    local src_apk_file="${SRC_FOLDER}/${apk_file_name}"
    local src_perm_file="${SRC_FOLDER}/${perm_file_name}"

    [[ ! -f "${src_apk_file}" ]] && return 21
    [[ ! -f "${src_perm_file}" ]] && return 31

    local dst_apk_folder="${PRIV_APP_FOLDER}/${apk_folder_name}"
    local dst_apk_file="${dst_apk_folder}/${apk_file_name}"
    local dst_perm_file="${PERMISSIONS_FOLDER}/${perm_file_name}"

    # Add controls or it may soft brick the phone...

    adb shell 'mkdir "${dst_apk_folder}"'
    adb push "${src_apk_file}" "${dst_apk_file}"
    adb shell 'chmod 755 "${dst_apk_folder}"'
    adb shell 'chmod 644 "${dst_apk_file}"'
    adb push "${src_perm_file}" "${dst_perm_file}"
    adb shell 'chmod 644 "${dst_perm_file}"'
}

#
# MAIN PROCESS
#

# Arrays initialisation
app_names=()
apk_folders=()
apk_names=()
perm_names=()

# Configuration for F-Droid Privileged Extension
app_names+=("F-Droid Privileged Extension")
apk_folders+=("F-DroidPrivilegedExtension")
apk_names+=("org.fdroid.fdroid.privileged.apk")
perm_names+=("privapp-permissions-org.fdroid.fdroid.privileged.xml")

print_info "Rebooting adb as root"
adb root

print_info "Mounting system partition"
adb remount

for i in ${!app_names[@]}; do
    print_info "Installing ${app_names[$i]}"
    install_system_app "${apk_folders[$i]}" "${apk_names[$i]}" "${perm_names[$i]}"
    case $? in
        0) print_info ">>>>>> F-Droid Privileged Extension installed";;
        10) print_warn ">>>>>> F-Droid Privileged Extension installation cancelled (invalid apk folder name)";;
        20) print_warn ">>>>>> F-Droid Privileged Extension installation cancelled (invalid apk file name)";;
        21) print_warn ">>>>>> F-Droid Privileged Extension installation cancelled (source apk file not found)";;
        30) print_warn ">>>>>> F-Droid Privileged Extension installation cancelled (invalid permissions file name)";;
        31) print_warn ">>>>>> F-Droid Privileged Extension installation cancelled (source permissions file not found)";;
        *) print_warn ">>>>>> F-Droid Privileged Extension installation cancelled";;
    esac
done

print_info "Rebooting adb as non root"
adb unroot
