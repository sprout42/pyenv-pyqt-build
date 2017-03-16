# generic utilities

no_system_version() {
    # Abort if the pyenv version is system
    version=`pyenv-version-name`
    if [ "$version" = "system" ]
    then
        >&2 echo "I am not allowed to install sip system-wide."
        >&2 echo "Please select a different python version first."
        exit 1
    fi
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
function http() {
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

function http_get_aria2c() {
  local out="${2:-$(mktemp "out.XXXXXX")}"
  if aria2c --allow-overwrite=true --no-conf=true -o "${out}" ${ARIA2_OPTS} "$1" >&4; then
    [ -n "$2" ] || cat "${out}"
  else
    false
  fi
}

function http_get_curl() {
  curl -q -o "${2:--}" -sSLf ${CURL_OPTS} "$1"
}

function http_get_wget() {
  wget -nv ${WGET_OPTS} -O "${2:--}" "$1"
}
# ======================= #

# ======================= #
# get the tar files, unpack, compile and install

# Exit with the given error and message
# Parameters
# err (int): error code
# msg (string): optional error message
function exit_on_error() {
    err=$1
    msg=$2

    if [ $err -gt 0 ]
    then
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
function get_file() {
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
# tar_dir (string): directory where the tar file is located
# tar_name (string): name of the tar file
# Returns:
# * exit_code (int): 0: un-tarring successful; otherwise: failure
function untar() {
    tar_dir=$1
    tar_name=$2

    set +e
    pushd $tar_dir
    tar -xzf $fname
    exit_code=$?
    popd
    set -e

    exit_on_error $exit_code "Failed to unpack $tar_dir/$fname"
}


# Go into the directory and run python configure.py
# Parameters
# * name (string): name of the thing that we are building
# * path (string): path where to execute the command
# Returns
# * error_code (int): error code from the python configure.py command
function configure() {
    local name=$1
    local path=$2

    set +e
    pushd $path
    echo "*** Configuring $name"
    python configure.py
    error_code=$?
    popd
    set -e

    exit_on_error $exit_code "*** Failed to configure $name"
}

# Go into the directory and run make
# Parameters
# * name (string): name of the thing that we are building
# * path (string): path where to execute the command
# * args (list): arguments passed to make
# Returns
# * error_code (int): error code from the make command
function make_() {
    local name=$1
    local path=$2
    shift 2
    local args="$*"

    set +e
    pushd $path
    echo "*** Run make $args on $name"
    if [ "x$args" = x ]
    then
        make
    else
        make "$args"
    fi
    error_code=$?
    popd
    set -e

    exit_on_error $error_code "*** Failed to make $args"
}

# Get the tar file, unpack and install it
# Parameters:
# * name (string): user friendly name of the package to install
# * url (string): url to fetch
# * dest_dir (string): directory where the tar files is to be downloaded
# * tar_name (string): name of the tar file
# * source_dir (string): name of the directory contained in "tar_name"
function get_and_install() {
    name=$1
    url=$2
    dest_dir=$3
    tar_name=$4
    source_dir=$5

    get_file $url $dest_dir/$tar_name
    untar $dest_dir $tar_name

    abs_source_dir=$dest_dir/$source_dir

    configure $name $abs_source_dir
    make_ $name $abs_source_dir
    make_ $name $abs_source_dir install
}
# ======================= #
