# generic utilities

# ======================= #
# Download the url and save it to the file.
# borrowed from https://github.com/pyenv/pyenv and modified

ARIA2_OPTS="${PYTHON_BUILD_ARIA2_OPTS} ${IPV4+--disable-ipv6=true} ${IPV6+--disable-ipv6=false}"
CURL_OPTS="${PYTHON_BUILD_CURL_OPTS} ${IPV4+--ipv4} ${IPV6+--ipv6}"
WGET_OPTS="${PYTHON_BUILD_WGET_OPTS} ${IPV4+--inet4-only} ${IPV6+--inet6-only}"

# parameters
# url (string): url to fetch
# file (string): name of the file where to save the url content
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
  local out="${2:-$(mktemp "out.XXXXXX")}"
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
