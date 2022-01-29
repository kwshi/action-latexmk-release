#!/bin/bash
set -euo pipefail
shopt -s nullglob dotglob extglob globstar

declare \
  TOKEN="$1" \
  TAG="$2" \
  PATTERNS="$3" \
  ENGINE="$4" \
  OUT="$5" \
  ARG_TEXINPUTS="$6" \
  ARG_SHELL="$7" \
  ARGS="$8" \
  UPLOAD_URL="https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases" \
  API_URL="https://api.github.com/repos/$GITHUB_REPOSITORY/releases"

declare -a CURL_API=(
  curl -fs
  -H "Authorization: Bearer $TOKEN"
  -H 'Accept: application/vnd.github.v3+json'
)

declare -a patterns paths=() args=()
declare -a texinput_patterns texinput_paths=() texinput_abspaths=()
declare path pdf id data url texinputs

function percent-encode {
  local encoded='' c
  for (( i=0; i<${#1}; ++i )); do
    c="${1:i:1}"
    case "$c" in
      [0-9A-Za-z_.~-]) encoded="$encoded$c";;
      *) printf -v encoded "%s%%%02x" "$encoded" "'$c";;
    esac
  done
  echo "$encoded"
}

# process latexmk arguments
{
  echo '::group::Preparing latexmk arguments'

  # default args
  args+=('-interaction=nonstopmode' '-halt-on-error')

  # engine
  case "$ENGINE" in
    'lualatex'|'pdflatex'|'xelatex') args+=("-$ENGINE");;
    *) echo "::error::Unrecognized LaTeX engine ${ENGINE@Q}"; exit 1;;
  esac

  # output directory
  args+=("-output-directory=$OUT")

  # shell escape
  if [[ "$ARG_SHELL" == 'true' ]]; then args+=('-shell-escape'); fi

  # extra args: temporarily disable globbing, keep splitting
  # shellcheck disable=SC2206
  set -f && args+=($ARGS) && set +f

  # log args for debugging purposes
  echo 'latexmk arguments:'
  for arg in "${args[@]}"; do echo "  ${arg@Q}"; done

  echo '::endgroup::'
}

# processing texinput paths
{
  echo '::group::Preparing TEXINPUTS search path'
  declare abs
  readarray -t texinput_patterns <<< "$ARG_TEXINPUTS"
  for pattern in "${texinput_patterns[@]}"; do
    # shellcheck disable=SC2206
    IFS= texinput_paths+=($pattern)
  done

  echo 'found paths:'
  for path in "${texinput_paths[@]}"; do
    abs="$(realpath -- "$path")"
    texinput_abspaths+=("$abs")
    echo "  ${path@Q} (absolute ${abs@Q})"
  done

  IFS=':' texinputs="${texinput_abspaths[*]}:"
  echo "collated search path: ${texinputs@Q}"

  echo '::endgroup::'
}

# glob source files
{
  echo '::group::Finding source files'
  readarray -t patterns <<< "$PATTERNS"
  for pattern in "${patterns[@]}"; do
    # shellcheck disable=SC2206
    IFS= paths+=($pattern)
  done
  for path in "${paths[@]}"; do
    echo "$path"
    if [[ ! -e "$path" ]]; then
      echo "::error::No path matching ${path@Q}"
      exit 1
    fi
  done
  echo '::endgroup::'
}

# compile pdfs
{
  for path in "${paths[@]}"; do
    echo "::group::Compiling ${path@Q}"
    pushd "$(dirname -- "$path")"
    TEXINPUTS="$texinputs" latexmk "${args[@]}" "$(basename -- "$path")"
    popd
    echo '::endgroup::'
  done
}

# setup release
{
  echo '::group::Creating release'
  if id="$(
    "${CURL_API[@]}" "$API_URL/tags/$(percent-encode "$TAG")" \
      | jq -rc '.id'
          )"; then
          "${CURL_API[@]}" -S -X 'DELETE' "$API_URL/$id"
  fi
  data="$(jq -cn --arg 'tag' "$TAG" '{tag_name: $tag}')"
  id="$("${CURL_API[@]}" -S -d "$data" "$API_URL" | jq -rc '.id')"
  echo '::endgroup::'
}

# upload pdfs
{
  echo '::group::Uploading release assets'
  for path in "${paths[@]}"; do
    pushd "$(dirname -- "$path")/$OUT"
    name="$(basename -s '.latex' -- "$(basename -s '.tex' -- "$path")")"

    url="$(
      "${CURL_API[@]}" -S \
        -H 'Content-Type: application/pdf' \
        --data-binary "@$pdf" \
        "$UPLOAD_URL/$id/assets?name=$(
          percent-encode "$pdf"
        )&label=$(
          percent-encode "$pdf"
        )" | jq -rc '.browser_download_url'
    )"
    popd

    echo "${pdf@Q}: $url"
  done
  echo '::endgroup::'
}
