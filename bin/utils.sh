# bash (comment to make vim properly handle bash syntax)
#
# generic utilities

no_system_version() {
    # Abort if the pyenv version is system
    version=$(pyenv-version-name)
    if [ "$version" = "system" ]
    then
        echo -e "I am not allowed to install sip system-wide.\nPlease select a different python version first." >&2
        exit 1 
    fi
}

utils_avail() {
    utils_msg="The following utils are required to use this pyenv-plugin:\n\tcurl, jq, xq (yq), pup"
    # Check if the utilites used by this script are availabke
    _out=$(curl --help)
    if [ $? -ne 0 ]; then
        echo -e "${utils_msg}" >2&
        exit 1
    fi

    _out=$(jq --help)
    if [ $? -ne 0 ]; then
        echo -e "${utils_msg}" >2&
        exit 1
    fi

    _out=$(xq --help)
    if [ $? -ne 0 ]; then
        echo -e "${utils_msg}" >2&
        exit 1
    fi

    _out=$(pup --help)
    if [ $? -ne 0 ]; then
        echo -e "${utils_msg}" >2&
        exit 1
    fi
}

# Process the arguments, this should will set the following variables that allow 
# us to process the appropriate action:
# * sw_version
# * config_args
# * qmake_path (used only for PyQT* modules)
#
# This function requires the following variables to be set:
# * sw_name
# * config_args
#       any required configuration options can be set before calling this 
#       function and be maintained
#
# This function requires the following functions to be defined:
# * usage
# * print_versions
# * update_versions
process_pyqt_build_cli() {
    # Process CLI parameters
    _DO_INSTALL=0
    while [ $# -gt 0 ]; do
        arg="$1"

        case "$arg" in
        "-h" | "--help" )
            usage 0
            ;;
        "update" )
            update_versions

            # Add "latest" which will be the last version and "default" which 
            # means match the current installed QT version.
            echo "latest"
            if [ "${sw_name}" != "sip" ]; then
                echo "default"
            fi
            exit 0
            ;;
        "versions" )
            # Print the possible versions that can be installed
            print_versions

            # Add "latest" which will be the last version and "default" which means 
            # match the current installed QT version.
            echo "latest"
            if [ "${sw_name}" != "sip" ]; then
                echo "default"
            fi
            exit 0
            ;;
        "show" )
            # Installed PyQt* version
            if [ "${sw_name}" != "sip" ]; then
                sw_version=$(get_installed_version "${sw_name}")
                echo "${sw_name} ${sw_version} installed"
            fi

            # Installed SIP version
            sip_version=$(get_installed_version sip)
            echo "sip ${sip_version} installed"

            if [ "${sw_name}" != "sip" ]; then
                # PyQt* & SIP API versions
                print_api_versions "${sw_name}"
            else
                # SIP API version
                sip_py_ver=$(get_current_sip_version)
                echo "sip API version: ${sip_py_ver}"
            fi

            exit 0
            ;;
        "uninstall" )
            uninstall "${sw_name}"
            exit 0
            ;;
        "install" )
            # set "default" as the default version to install, this may get 
            # overridden later
            _DO_INSTALL=1
            sw_version="default"
            ;;
        * )
            # If sw_version is set to "default" then this must be the version number 
            # to install
            set +e
            is_version_string "${arg}"
            is_ver=$?
            set -e

            if [ "${sw_version}" == "default" ] && [ $is_ver == 0 ]; then
                sw_version="$arg"
            elif [ "${sw_name}" != "sip" ] && [ "${arg}" == "--qmake" ] && [ $# -ge 2 ]; then
                # Set the qmake path to the next argument and shift the argument 
                # list one extra position
                qmake_path="$2"
                shift
            else
                # Allow extra configuration arguments to be passed as command line 
                # parameters
                config_args="${config_args} ${arg}"
            fi
            ;;
        esac

    shift # Keep processing args
    done

    # Only the install command is not handled in the previous loop, if we have 
    # reached this far ensure that the "install" subcommand was provided
    if [ $_DO_INSTALL -eq 0 ]; then
        usage 1 >&2
    fi

    # Export the arguments required to run the command
    export sw_version="${sw_version}"
    export qmake_path="${qmake_path}"
    export config_args="${config_args}"
}

# Checks that the installed QT version is compatible with the desired PyQt 
# version being installed
#
# This function requires the following variables to be set:
# * sw_name
# * sw_version
# * qmake_path
#
# The following variables will be set after this function runs:
# * qt_version
check_qt_version() {
    if [ -z "${qmake_path}" ]; then
        echo "Unable to determine installed QT version, use the --qmake argument" >&2
        exit 1
    fi

    qt_version=$("${qmake_path}" -query | sed -n 's/QT_VERSION://p')
    if [ -z "${qt_version}" ]; then
        echo "Unable to determine QT version with \"${qmake_path} -query\", stopping install" >&2
        exit 1
    fi

    # if the sw_version is default, set it to the detected qt_version
    if [ "${sw_version}" == "default" ]; then
        sw_version="${qt_version}"
    elif [ "${qt_version}" != "${sw_version}" ]; then
        # The installed QT (qmake -query) and selected PyQT version to install must 
        # match
        echo "Unable to install ${sw_name} ${sw_version}, QT version is ${qt_version}" >&2
        echo "Use --qmake option to specify correct qmake executable for ${sw_name} ${sw_version}" >&2
        exit 1
    fi

    # Export the arguments required to run the command
    export qt_version="${qt_version}"
}

# ======================= #
# Download the url and save it to the file.
# borrowed from https://github.com/pyenv/pyenv and modified

ARIA2_OPTS="${PYTHON_BUILD_ARIA2_OPTS} ${IPV4+--disable-ipv6=true} ${IPV6+--disable-ipv6=false}"
CURL_OPTS="${PYTHON_BUILD_CURL_OPTS} ${IPV4+--ipv4} ${IPV6+--ipv6}"
WGET_OPTS="${PYTHON_BUILD_WGET_OPTS} ${IPV4+--inet4-only} ${IPV6+--inet6-only}"

# parameters
# * url (string): url to fetch
# * file (string): name of the file where to save the url content
http() {
    local method="get"
    local url="$1"
    local file="$2"
    [ -n "$url" ] || return 1

    if type aria2c &>/dev/null; then
        "http_${method}_aria2c" "$url" "$file"
    elif type curl &>/dev/null; then
        "http_${method}_curl" "$url" "$file"
    elif type wget &>/dev/null; then
        "http_${method}_wget" "$url" "$file"
    else
        echo "error: please install \`aria2c\`, \`curl\` or \`wget\` and try again" >&2
        exit 1
    fi
}

http_get_aria2c() {
    local out="${2:-$(mktemp -t "out.XXXXXX")}"
    if aria2c --allow-overwrite=true --no-conf=true -o "${out}" ${ARIA2_OPTS} "$1" >&4; then
        [ -n "$2" ] || cat "${out}"
    else
        false
    fi
}

http_get_curl() {
    curl -q -o "${2:--}" -sSLf ${CURL_OPTS} "$1"
}

http_get_wget() {
    wget -nv ${WGET_OPTS} -O "${2:--}" "$1"
}
# ======================= #

# ======================= #
# get the tar files, unpack, compile and install

# Exit with the given error and message
# Parameters
# err (int): error code
# msg (string): optional error message
exit_on_error() {
    err=$1
    msg=$2

    if [ $err -ne 0 ]; then
        if [ "x$msg" != "x" ]
        then
            echo $msg >&2
        fi
        exit $err
    fi
}

# Get the tar file and return the exit code of the command to fetch
# Parameters:
# * url (string): url to fetch
# * dest_file (string): name of the file where to save the url content
# Returns:
# * exit_code (int): 0: url successfully fetched; otherwise: failure
get_file() {
    url=$1
    dest_file=$2

    set +e
    http $url $dest_file
    exit_code=$?
    set -e

    exit_on_error $exit_code "Failed to download $url"
}

# Un-tar the retrieved file
# Parameters:
# * tar_dir (string): directory where the tar file is located
# * tar_name (string): name of the tar file
# * sw_dirname (string): name of the directory expected after the tarball is 
#                        unpacked
# Returns:
# * exit_code (int): 0: un-tarring successful; otherwise: failure
untar() {
    tar_dir=$1
    tar_name=$2
    sw_dirname=$3

    # if target directory already exists don't bother unpacking the tarball, 
    # this package may have already been configured or built and there is no 
    # need to re-do all that work.
    if [ -d "${tar_dir}/${sw_dirname}" ]; then
        return 0
    fi

    set +e
    curdir=$(pwd)
    cd "${tar_dir}"
    tar -xzf $fname
    exit_code=$?
    cd "${curdur}"
    set -e

    exit_on_error $exit_code "Failed to unpack $tar_dir/$fname"

    # Ensure the target directory exists now
    if [ ! -d "${tar_dir}/${sw_dirname}" ]; then
        echo "After unpacking ${tar_name}, expected directory ${tar_dir}/${sw_dirname} not created" >&2
        exit 1
    fi
}


# Go into the directory and run python configure.py
# Parameters
# * name (string): name of the thing that we are building
# * path (string): path where to execute the command
# * args (string): Any remaining arguments are passed to configure
# Returns
# * error_code (int): error code from the python configure.py command
configure() {
    local name="$1"
    local path="$2"

    if [ $# -ge 3 ]; then
        args="${@:3}"
    fi

    curdir=$(pwd)
    cd "${path}"

    if [ ! -f "configure.py" ] && [ -f "build.py" ]; then
        # Check if prepare needs to be run first
        echo "*** Preparing $name"
        python build.py prepare
    fi

    if [ -f "configure.py" ]; then
        echo "*** Configuring ${name} ${args}"
        python configure.py ${args}
    else
        echo "Don't know how to configure ${name} in ${path}" >&2
        exit 1
    fi

    cd "${curdur}"
}

# Go into the directory and run make
# Parameters
# * name (string): name of the thing that we are building
# * path (string): path where to execute the command
# * args (list): arguments passed to make
# Returns
# * error_code (int): error code from the make command
make_() {
    local name=$1
    local path=$2
    shift 2
    local args="$*"

    set +e
    curdir=$(pwd)
    cd "${path}"
    echo "*** Run make $args on $name"
    if [ "x$args" = x ]
    then
        make
    else
        make "$args"
    fi
    error_code=$?
    cd "${curdur}"
    set -e

    exit_on_error $error_code "*** Failed to make $args"
}

# Get the tar file, and unpack it
# Parameters:
# * name (string): user friendly name of the package to install
# * url (string): url to fetch
# * dest_dir (string): directory where the tar files is to be downloaded
# * sw_dirname (string): name of the directory expected after the tarball is 
#                        unpacked
# * tar_name (string): name of the tar file
# * tar_sha256 (string): hash for downloaded file, if provided will validate 
#                        existing file if it exists before re-downloading
download() {
    name=$1
    url=$2
    dest_dir=$3
    sw_dirname=$4
    tar_name=$5

    if [ $# -ge 6 ]; then
        tar_sha256=$6
    fi

    # output to FD 3 so the output from this function does not interfere with 
    # the ability of calling functions to return values

    if [ -f "${dest_dir}/${tar_name}" ]; then
        if [ ! -z "${tar_sha256}" ]; then
            echo "Validating existing download ${tar_name}" >&3
            set -e
            echo "${tar_sha256} ${dest_dir}/${tar_name}" | sha256sum -c >&3
        else
            echo "*** Unable to validate existing download ${tar_name}, removing" >&3
            rm "${dest_dir}/${tar_name}"
        fi
    fi

    if [ ! -f "${dest_dir}/${tar_name}" ]; then
        echo "Downloading ${sw_name} ${sw_version}" >&3
        get_file $url $dest_dir/$tar_name
    fi

    untar $dest_dir $tar_name $sw_dirname
}

# Return a pyenv version-specific directory that can be used to store state 
# files and source
get_pyqt_dir() {
    #realpath "$(dirname ${BASH_SOURCE[0]})/.."
    dir="$(pyenv prefix)/share/pyqt-build"
    if [ ! -d "${dir}" ]; then
        mkdir -p "${dir}"
    fi
    echo "${dir}"
}

# Get directory to build a package in
# Parameters:
# * sw_name (string): user friendly name of the package to install
get_cache_dir() {
    sw_name=$1

    # Use the pyqt-build cache directory so if a version is already built for an 
    # existing pyenv version it can just be installed for the current version
    pyqt_dir=$(realpath "$(dirname ${BASH_SOURCE[0]})/..")
    cache_dir="${pyqt_dir}/cache/${sw_name}"

    if [ ! -d "${cache_dir}" ]; then
        mkdir -p "${cache_dir}"
    fi

    echo "${cache_dir}"
}

# Indicates if a supplied argument is a valid version string or not
is_version_string() {
    [[ $1 =~ ^[0-9.]+$ ]]
}

# Get PyQT required minimum SIP version
# Parameters
# * src_dir (string): path to the unpacked PyQT source
get_required_sip_version() {
    src_dir="$1"

    curdir=$(pwd)
    cd "${src_dir}"

    set -e
    sip_ver=$(python -c "import configure;print(configure.SIP_MIN_VERSION)" 2> /dev/null)

    cd "${curdir}"

    echo "${sip_ver}"
}

# Because bash can't do simple version string comparisons like:
#   [ "1.2.3" >= "1.2.2" ]
# we have to make this function
#
# Returns 1 if arg1 is greater, 2 if arg2 is greater or 0 if they are equal
compare_versions() {
    local v1=( $(echo "$1" | tr '.' ' ') )
    local v2=( $(echo "$2" | tr '.' ' ') )

    local len=${#v1[*]}
    if [ ${#v1[*]} -lt ${#v2[*]} ]; then
        len=${#v2[*]}
    fi

    for i in seq $len; do
        [ "${v1[i]:-0}" -gt "${v2[i]:-0}" ] && return 1
        [ "${v1[i]:-0}" -lt "${v2[i]:-0}" ] && return 2
    done

    return 0
}

# Print the PyQt* and SIP API versions as reported from python
# this function only works for PyQt5 and PyQt4, cannot be used to get SIP API 
# versions directly.
print_api_versions() {
    sw_name=$1

    python <(cat <<EOF
from ${sw_name}.QtCore import QT_VERSION_STR
from sip import SIP_VERSION_STR
print('${sw_name} API version: %s' % QT_VERSION_STR)
print('sip API version: %s' % SIP_VERSION_STR)
EOF
)
}


# Print currently installed SIP version
get_current_sip_version() {
    #   from sip import SIP_VERSION_STR
    #   print(SIP_VERSION_STR)
    #
    # only works after PyQt*.QtCore or PyQt*.Qt have been imported
    #
    # a non-PyQt* based solution is:
    #   import sipconfig
    #   print(sipconfig._pkg_config['sip_version_str'])
    python -c "import sipconfig;print(sipconfig._pkg_config['sip_version_str'])"
}

check_sip_version() {
    sw_name="$1"
    sw_version="$2"
    src_dir="$3"

    pyqt_sip_ver=$(get_required_sip_version "${src_dir}")
    cur_sip_ver=$(get_current_sip_version)

    # Per: 
    #     https://www.riverbankcomputing.com/static/Docs/PyQt5/building_with_configure.html
    #
    # When configuring PyQt5 5.11+ the following configuration option must be 
    # provided:
    # --sip-module PyQt5.sip
    compare_versions "${sw_version}" "5.11.0"
    # $? < 2 means 0 (equal) or 1 (target version is > 5.11)
    if [ $? -lt 2 ]; then
        sip_private_module=1
    else
        sip_private_module=0
    fi

        sip_configure_args="--sip-module PyQt5.sip"

    if [ -z "${cur_sip_ver}" ]; then
        echo "*** SIP not installed, installing ${sw_name} ${sw_version} minimum SIP version: ${pyqt_sip_ver}"
        pyenv-sip install "${pyqt_sip_ver}" "${sip_configure_args}"
    else
        compare_versions "${cur_sip_ver}" "${pyqt_sip_ver}"
        # A result of 2 means the second version is greater.  Also confirm that 
        # the major version numbers match exactly.
        if [ $? -eq 2 ] || [ "${cur_sip_ver::2}" != "${pyqt_sip_ver::2}" ]; then
            echo "*** SIP ${cur_sip_ver} installed, but ${sw_name} ${sw_version} requires ${pyqt_sip_ver}, please install the correct SIP version"
            exit 1
        elif [ ${sip_private_module} -eq 1 ]; then
            # If sip is already installed then the --no-tools option can be to 
            # just configure and install the required "private module"
            sip_configure_args="${sip_configure_args} --no-tools"

            echo "*** Configuring and installing SIP private module required by ${sw_name} ${sw_version}"
            pyenv-sip install "${pyqt_sip_ver}" "${sip_configure_args}"
        fi
    fi
}

# Build the source
# Parameters:
# * sw_name (string): user friendly name of the package to install
# * sw_version (string): used for tracking installed files
# * src_dir (string): path to the source
# * configure_args (string): if provided it will be supplied during config
compile() {
    sw_name="$1"
    sw_version="$2"
    src_dir="$3"

    if [ $# -ge 4 ]; then
        configure_args="${@:4}"
    fi

    configure "${sw_name}" "${src_dir}" "${configure_args}"

    echo "*** Compiling ${sw_name} ${sw_version}"
    make_ "${sw_name}" "${src_dir}"

    echo "*** Installing ${sw_name} ${sw_version}"

    make_ "${sw_name}" "${src_dir}" install

    # Save which version was compiled and the installed files
    echo "${sw_version}" > "$(get_pyqt_dir)/.${sw_name}_installed_version"
    cp "${src_dir}/installed.txt" "$(get_pyqt_dir)/.${sw_name}_installed_files"
}

uninstall() {
    sw_name=$1

    install_list="$(get_pyqt_dir)/.${sw_name}_installed_files"
    version_file="$(get_pyqt_dir)/.${sw_name}_installed_version"

    # PyQt packages will show up in pip regardless of how they are installed, if 
    # one shows up in pip but there is no version file it means it was probably 
    # installed through pip and still counts as installed.
    if [ "${sw_name}" != "sip" ]; then
        set +e
        pip_version=$(python -m pip --no-python-version-warning show "${sw_name}" | sed -n 's/^Version: //p')
        set -e
    fi

    if [ ! -z "${pip_version}" ]; then
        echo "*** Uninstalling ${sw_name} ${pip_version}"
    elif [ -f "${install_list}" ] && [ -f "${version_file}" ]; then
        sw_version=$(cat "${version_file}")
        echo "*** Uninstalling ${sw_name} ${sw_version}"
    elif [ -f "${install_list}" ] || [ -f "${version_file}" ]; then
        echo "*** Uninstalling incomplete ${sw_name} install"
    else
        echo "No ${sw_name} version installed" >&2
        exit 1
    fi

    # First attempt uninstalling through pip
    if [ ! -z "${pip_version}" ]; then
        set +e
        python -m pip --no-python-version-warning uninstall -y "${sw_name}" 
        set -e
    fi

    # Even if pip uninstall just happened, double check that all of the 
    # installed files are cleaned up if a list of installed files exists.
    if [ -f "${install_list}" ]; then
        installed_files=( $(cat "${install_list}") )
        for file in "${installed_files[@]}"; do
            if [ -d "${file}" ]; then
                echo "rm -rf ${file}"
                rm -rf "${file}"
            else
                echo "rm -f ${file}"
                rm -f "${file}"
            fi
        done

        echo "rm -f ${install_list}"
        rm -f "${install_list}"
    fi

    if [ -f "${version_file}" ]; then
        echo "rm -f ${version_file}"
        rm -f "${version_file}"
    fi

    # Don't remove already compiled and installed src packages, those can be 
    # saved for later use
}

# * sw_name (string): user friendly name of the package to install
get_installed_version() {
    sw_name=$1

    # PyQt packages will show up in pip regardless of how they are installed, if 
    # one shows up in pip but there is no version file it means it was probably 
    # installed through pip and still counts as valid.
    if [ "${sw_name}" != "sip" ]; then
        set +e
        pip_version=$(python -m pip --no-python-version-warning show "${sw_name}" | sed -n 's/^Version: //p')
        set -e
    fi

    version_file="$(get_pyqt_dir)/.${sw_name}_installed_version"
    if [ -f "${version_file}" ]; then
        cat "${version_file}"
    elif [ ! -z "${pip_version}" ]; then
        echo "${pip_version}"
    else
        echo "No ${sw_name} version installed" >&2
        exit 1
    fi
}

# Construct the download URL and build directory name, then download and install
# Parameters:
# * sw_name (string): user friendly name of the package to install
# * sw_version (string): Version to install
get_source() {
    sw_name=$1
    sw_version=$2

    # Annoyingly the URL directory and tarball names are different in an 
    # inconsistent way for each package
    if [ "${sw_name}" == "PyQt4" ]; then
        # the pyqt version number contains the platform
        cur_plat_name=$(uname)
        if [ "${cur_plat_name}" == "Linux" ]; then
            sw_plat_name="gpl_x11"
        elif [ "${cur_plat_name}" = "Darwin" ]; then
            sw_plat_name="gpl_mac"
        else
            #echo "The platform $uname is not supported" >&2
            #exit 1
            sw_plat_name="gpl_win"
        fi
        sw_dir_prefix="${sw_name}_${sw_plat_name}"
        url_dirname="PyQt"
    elif [ "${sw_name}" == "PyQt5" ]; then
        sw_dir_prefix="${sw_name}_gpl"
        url_dirname="PyQt"
    elif [ "${sw_name}" == "sip" ]; then
        sw_dir_prefix="${sw_name}"
        url_dirname="${sw_name}"
    else
        echo "Unknown SW ${sw_name}" >&2
        exit 1
    fi

    # name of tarball
    sw_dirname="${sw_dir_prefix}-${sw_version}"
    fname="${sw_dirname}.tar.gz"
    cache_dir=$(get_cache_dir "${sw_name}")
    src_dir="${cache_dir}/${sw_dirname}"

    # If the destination dir already exists there is no need to re-download or 
    # check the tarball, we don't want to break a version that is already 
    # unpacked, configured, and built
    if [ -d "${src_dir}" ]; then
        echo "${fname} already downloaded and unpacked" >&3
    else
        url="https://sourceforge.net/projects/pyqt/files/${sw_name}/${url_dirname}-${sw_version}/${fname}"
        download "${sw_name}" "${url}" "${cache_dir}" "${sw_dirname}" "${fname}"
    fi

    # Return the path that the source is now in
    echo "${src_dir}"
}

# Construct the download pypi sdist URL and build directory name, then download 
# and install
# Parameters:
# * sw_name (string): user friendly name of the package to install
# * sw_version (string): Version to install
get_source_from_sdist() {
    sw_name=$1
    sw_version=$2

    sw_dirname="${sw_name}-${sw_version}"
    fname="${sw_dirname}.tar.gz"
    cache_dir=$(get_cache_dir "${sw_name}")
    src_dir="${cache_dir}/${sw_dirname}"

    # If the destination dir already exists there is no need to re-download or 
    # check the tarball, we don't want to break a version that is already 
    # unpacked, configured, and built
    if [ -d "${src_dir}" ]; then
        echo "${fname} already downloaded and unpacked" >&3
    else
        pypi_url="https://pypi.org/project/${sw_name}/${sw_version}/"

        # scrape the sdist package from pypi because riverbankcomputing is a bunch 
        # of jerks who can't just have a nice easy to read list of available source 
        # packages.
        set -e
        tmpfile=$(mktemp)
        curl -s "${pypi_url}" -o "${tmpfile}"
        url=$(cat "${tmpfile}" | pup "a:contains(\"${fname}\") attr{href}")
        tarball_sha256=$(cat "${tmpfile}" | pup ":parent-of(caption:contains(\"Hashes for ${fname}\")) :parent-of(:contains(\"SHA256\")) code text{}")
        rm "${tmpfile}"

        download "${sw_name}" "${url}" "${cache_dir}" "${sw_dirname}" "${fname}" "${tarball_sha256}"
    fi

    # Return the path that the source is now in
    echo "${src_dir}"
}

# Print the possible versions that can be installed with src releases
# * sw_name (string): user friendly name of the package
update_src_versions() {
    sw_name=$1

    if [ "${sw_name}" == "PyQt4" ]; then
        # "PyQt-<version>"
        prefix_len=5
    elif [ "${sw_name}" == "PyQt5" ]; then
        # "PyQt-<version>"
        prefix_len=5
    elif [ "${sw_name}" == "sip" ]; then
        # "sip-<version>"
        prefix_len=4
    else
        echo "Unknown SW ${sw_name}" >&2
        exit 1
    fi

    src_url="https://sourceforge.net/projects/pyqt/files/${sw_name}/"

    src_version_file="$(get_cache_dir)/.${sw_name}_src_versions"

    # This will do the printing in a hopefully platform-compatible way
    curl -s "${src_url}" | sed -n 's/net.sf.files =\(.*\);$/\1/p' | jq -r "keys[][${prefix_len}:]" | sort -V > "${src_version_file}"

    # return the versions
    cat "${src_version_file}"
}

# Print the possible versions that can be installed from mercurial
# * sw_name (string): user friendly name of the package
# * repo_url (string): URL of the repo itself
update_hg_versions() {
    sw_name=$1
    repo_url=$2

    hg_version_file="$(get_cache_dir)/.${sw_name}_hg_versions"

    curl -s "${repo_url}/json-tags" | sed -n '/^{$/,/^}$/ p' | jq -r '.tags[].tag' | sort -V > "${hg_version_file}"

    # return the versions
    cat "${hg_version_file}"
}

# download and save the possible versions that can be installed using pip
# * sw_name (string): user friendly name of the package
update_pip_versions() {
    sw_name=$1

    pip_version_file="$(get_cache_dir)/.${sw_name}_pip_versions"
    curl -s "https://pypi.org/rss/project/${sw_name}/releases.xml" | xq -r '.rss.channel.item[].title' | sort -V > "${pip_version_file}"

    # return the versions
    cat "${pip_version_file}"
}

# Print the possible versions that can be installed with src releases
# * sw_name (string): user friendly name of the package
print_src_versions() {
    sw_name=$1

    src_version_file="$(get_cache_dir)/.${sw_name}_src_versions"
    if [ -f "${src_version_file}" ]; then
        cat "${src_version_file}"
    else
        update_src_versions "${sw_name}"
    fi
}

# Print the possible versions that can be installed from mercurial
# * sw_name (string): user friendly name of the package
# * repo_url (string): URL of the repo itself
print_hg_versions() {
    sw_name=$1
    repo_url=$2

    hg_version_file="$(get_cache_dir)/.${sw_name}_hg_versions"
    if [ -f "${hg_version_file}" ]; then
        cat "${hg_version_file}"
    else
        update_hg_versions "${sw_name}" "${repo_url}"
    fi
}

# Print the possible versions that can be installed using pip
# * sw_name (string): user friendly name of the package
print_pip_versions() {
    sw_name=$1

    pip_version_file="$(get_cache_dir)/.${sw_name}_pip_versions"
    if [ -f "${pip_version_file}" ]; then
        cat "${pip_version_file}"
    else
        update_pip_versions "${sw_name}"
    fi
}

# Install requested package using pip or using the pypi sdist
# Parameters:
# * sw_name (string): package to install
# * sw_version (string): version to install
# * config_args (rest of arguments)
pip_install() {
    sw_name=$1
    sw_version=$2
    config_args=${@:3}

    # sip and PyQt5 can be installed with pip only if python is >=3.5 and if the 
    # system is at 64 bits
    is_greater_35=$(python -c 'import sys; print(sys.version_info >= (3, 5))')
    arch=$(uname -m)
    if [ $is_greater_35 = "True" ] && [ $arch = "x86_64" ]; then
        echo "*** Installing ${sw_name} ${sw_version} with pip"
        python -m pip --no-python-version-warning install "sip==${sw_version}" 2>/dev/null
        echo "*** ${sw_name} has been installed"
    else
        echo "*** Using ${sw_name} ${sw_version} sdist from pypi"
        src_dir=$(get_source_from_sdist "${sw_name}" "${sw_version}")
        compile "${sw_name}" "${sw_version}" "${src_dir}" "${config_args}"
    fi
}

# Install requested package from source
# * sw_name (string): package to install
# * sw_version (string): version to install
# * config_args (rest of arguments)
src_install() {
    sw_name=$1
    sw_version=$2
    config_args=${@:3}

    echo "*** Installing ${sw_name} ${sw_version} from source release"
    src_dir=$(get_source "${sw_name}" "${sw_version}")
    compile "${sw_name}" "${sw_version}" "${src_dir}" "${config_args}"
}

# Install requested package from mercurial source
# * sw_name (string): package to install
# * sw_version (string): version to install
# * config_args (rest of arguments)
hg_install() {
    sw_name=$1
    sw_version=$2
    config_args=${@:3}

    cache_dir=$(get_cache_dir "${sw_name}")

    echo "*** Building ${sw_name} ${sw_version} from mercurial source tag"
    hg clone "${sip_hg_repo}" -r "${sw_version}" "${cache_dir}/sip-hg-${sw_version}"
    compile "${sw_name}" "${sw_version}" "${cache_dir}/sip-hg-${sw_version}" "${config_args}"
}
