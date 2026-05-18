#!/usr/bin/env bash
set -euo pipefail

SOURCE_OWNER="${SOURCE_OWNER:-retoaccess1}"
SOURCE_REPO="${SOURCE_REPO:-haveno-reto}"
SITE_DIR="${SITE_DIR:-site}"
APT_DIST="${APT_DIST:-stable}"
APT_COMPONENT="${APT_COMPONENT:-main}"
APT_ORIGIN="${APT_ORIGIN:-Haveno Reto}"
APT_LABEL="${APT_LABEL:-Haveno Reto}"
APT_DESCRIPTION="${APT_DESCRIPTION:-Debian repository for Haveno Reto releases}"
SIGN_REPO="${SIGN_REPO:-false}"
APT_SIGNING_KEY_ID="${APT_SIGNING_KEY_ID:-}"
APT_SIGNING_PASSPHRASE="${APT_SIGNING_PASSPHRASE:-}"
APT_SIGNING_KEYRING_FILENAME="${APT_SIGNING_KEYRING_FILENAME:-haveno-repo-archive-keyring.gpg}"
api_base="https://api.github.com/repos/${SOURCE_OWNER}/${SOURCE_REPO}"
release_api="${api_base}/releases"

pool_dir="${SITE_DIR}/pool/${APT_COMPONENT}"
dist_root="${SITE_DIR}/dists/${APT_DIST}"
component_root="${dist_root}/${APT_COMPONENT}"
tmp_dir="$(mktemp -d)"
assets_tsv="${tmp_dir}/assets.tsv"

token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)
if [[ -n "${token}" ]]; then
  api_headers+=(-H "Authorization: Bearer ${token}")
fi

cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

is_true() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd curl
require_cmd jq
require_cmd dpkg-deb
require_cmd apt-ftparchive
require_cmd gzip
if is_true "${SIGN_REPO}"; then
  require_cmd gpg
fi

mkdir -p "${pool_dir}" "${component_root}"
: > "${assets_tsv}"

echo "Fetching release metadata from ${SOURCE_OWNER}/${SOURCE_REPO}..."

page=1
declare -A seen_names=()

while :; do
  page_json="$(
    curl -fsSL \
      "${api_headers[@]}" \
      "${release_api}?per_page=100&page=${page}"
  )"

  page_count="$(jq 'length' <<<"${page_json}")"
  if [[ "${page_count}" == "0" ]]; then
    break
  fi

  while IFS=$'\t' read -r release_tag asset_name asset_url asset_size; do
    if [[ -z "${asset_name}" || -z "${asset_url}" ]]; then
      continue
    fi
    if [[ -n "${seen_names[${asset_name}]+x}" ]]; then
      continue
    fi
    seen_names["${asset_name}"]=1
    printf '%s\t%s\t%s\t%s\n' "${release_tag}" "${asset_name}" "${asset_url}" "${asset_size}" >> "${assets_tsv}"
  done < <(
    jq -r '
      .[]
      | select((.draft | not) and (.prerelease | not))
      | .tag_name as $tag
      | .assets[]
      | select(.name | endswith(".deb"))
      | [$tag, .name, .browser_download_url, (.size | tostring)]
      | @tsv
    ' <<<"${page_json}"
  )

  page=$((page + 1))
done

asset_count="$(wc -l < "${assets_tsv}" | tr -d ' ')"
if [[ "${asset_count}" == "0" ]]; then
  echo "No .deb assets found in ${SOURCE_OWNER}/${SOURCE_REPO} releases." >&2
  exit 1
fi

echo "Downloading ${asset_count} Debian packages..."
declare -A wanted_assets=()
while IFS=$'\t' read -r _release_tag asset_name _asset_url _asset_size; do
  wanted_assets["${asset_name}"]=1
done < "${assets_tsv}"

while IFS= read -r existing_deb; do
  [[ -z "${existing_deb}" ]] && continue
  base_name="$(basename "${existing_deb}")"
  if [[ -z "${wanted_assets[${base_name}]+x}" ]]; then
    echo "  - Removing obsolete package: ${base_name}"
    rm -f "${existing_deb}"
  fi
done < <(find "${pool_dir}" -maxdepth 1 -type f -name '*.deb')

while IFS=$'\t' read -r release_tag asset_name asset_url asset_size; do
  target="${pool_dir}/${asset_name}"
  expected_size="${asset_size:-0}"

  if [[ -f "${target}" ]]; then
    actual_size="$(stat -c%s "${target}")"
    if [[ "${expected_size}" != "0" && "${actual_size}" != "${expected_size}" ]]; then
      echo "  - Size mismatch for ${asset_name}, re-downloading"
      rm -f "${target}"
    elif ! dpkg-deb -f "${target}" Package >/dev/null 2>&1; then
      echo "  - Corrupted package ${asset_name}, re-downloading"
      rm -f "${target}"
    else
      continue
    fi
  fi

  echo "  - ${asset_name} (${release_tag})"
  tmp_target="${target}.tmp"
  rm -f "${tmp_target}"
  curl -fsSL --retry 3 --retry-delay 2 -o "${tmp_target}" "${asset_url}"
  dpkg-deb -f "${tmp_target}" Package >/dev/null 2>&1
  if [[ "${expected_size}" != "0" ]]; then
    downloaded_size="$(stat -c%s "${tmp_target}")"
    if [[ "${downloaded_size}" != "${expected_size}" ]]; then
      echo "Downloaded file size mismatch for ${asset_name}: expected ${expected_size}, got ${downloaded_size}" >&2
      rm -f "${tmp_target}"
      exit 1
    fi
  fi
  mv "${tmp_target}" "${target}"
done < "${assets_tsv}"

mapfile -t deb_files < <(find "${pool_dir}" -maxdepth 1 -type f -name '*.deb' | sort)
if [[ "${#deb_files[@]}" -eq 0 ]]; then
  echo "No downloaded .deb files found in ${pool_dir}." >&2
  exit 1
fi

declare -A arch_seen=()
for deb_file in "${deb_files[@]}"; do
  arch="$(dpkg-deb -f "${deb_file}" Architecture | tr -d '\n')"
  if [[ -z "${arch}" ]]; then
    echo "Unable to detect package architecture for ${deb_file}" >&2
    exit 1
  fi
  arch_seen["${arch}"]=1
done

mapfile -t all_arches < <(printf '%s\n' "${!arch_seen[@]}" | sort)

all_packages="${tmp_dir}/Packages.all"
apt-ftparchive packages "${pool_dir}" > "${all_packages}"

for arch in "${all_arches[@]}"; do
  binary_dir="${component_root}/binary-${arch}"
  mkdir -p "${binary_dir}"

  awk -v target_arch="${arch}" '
    BEGIN {
      RS = "";
      ORS = "\n\n";
    }
    {
      pkg_arch = "";
      line_count = split($0, lines, "\n");
      for (i = 1; i <= line_count; i++) {
        if (index(lines[i], "Architecture: ") == 1) {
          pkg_arch = substr(lines[i], 15);
          break;
        }
      }
      if (pkg_arch == "") {
        next;
      }

      if (target_arch == "all") {
        if (pkg_arch == "all") {
          print $0;
        }
      } else {
        if (pkg_arch == target_arch || pkg_arch == "all") {
          print $0;
        }
      }
    }
  ' "${all_packages}" > "${binary_dir}/Packages"

  gzip -9c "${binary_dir}/Packages" > "${binary_dir}/Packages.gz"
done

release_arches=()
for arch in "${all_arches[@]}"; do
  if [[ "${arch}" != "all" ]]; then
    release_arches+=("${arch}")
  fi
done
if [[ "${#release_arches[@]}" -eq 0 ]]; then
  release_arches=("all")
fi
if [[ -n "${arch_seen[all]+x}" ]]; then
  release_arches+=("all")
fi

mapfile -t release_arches < <(printf '%s\n' "${release_arches[@]}" | awk 'NF && !seen[$0]++')
release_arches_str="$(printf '%s ' "${release_arches[@]}" | sed 's/[[:space:]]*$//')"

apt_conf="${tmp_dir}/apt-ftparchive-release.conf"
cat > "${apt_conf}" <<EOF
APT::FTPArchive::Release {
  Origin "${APT_ORIGIN}";
  Label "${APT_LABEL}";
  Suite "${APT_DIST}";
  Codename "${APT_DIST}";
  Architectures "${release_arches_str}";
  Components "${APT_COMPONENT}";
  Description "${APT_DESCRIPTION}";
};
EOF

apt-ftparchive -c "${apt_conf}" release "${dist_root}" > "${dist_root}/Release"

if is_true "${SIGN_REPO}"; then
  if [[ -z "${APT_SIGNING_KEY_ID}" ]]; then
    echo "SIGN_REPO is enabled, but APT_SIGNING_KEY_ID is empty." >&2
    exit 1
  fi

  keyring_path="${SITE_DIR}/${APT_SIGNING_KEYRING_FILENAME}"
  gpg --batch --yes --output "${keyring_path}" --export "${APT_SIGNING_KEY_ID}"

  gpg_sign_args=(
    --batch
    --yes
    --pinentry-mode
    loopback
    --local-user
    "${APT_SIGNING_KEY_ID}"
  )
  rm -f "${dist_root}/InRelease" "${dist_root}/Release.gpg"
  if [[ -n "${APT_SIGNING_PASSPHRASE}" ]]; then
    gpg_sign_args+=(--passphrase-fd 0)
    printf '%s' "${APT_SIGNING_PASSPHRASE}" | gpg "${gpg_sign_args[@]}" --output "${dist_root}/InRelease" --clearsign "${dist_root}/Release"
    printf '%s' "${APT_SIGNING_PASSPHRASE}" | gpg "${gpg_sign_args[@]}" --output "${dist_root}/Release.gpg" --detach-sign "${dist_root}/Release"
  else
    gpg "${gpg_sign_args[@]}" --output "${dist_root}/InRelease" --clearsign "${dist_root}/Release"
    gpg "${gpg_sign_args[@]}" --output "${dist_root}/Release.gpg" --detach-sign "${dist_root}/Release"
  fi
fi

if is_true "${SIGN_REPO}"; then
  repo_key_line="<p>Repository key: <a href=\"./${APT_SIGNING_KEYRING_FILENAME}\">${APT_SIGNING_KEYRING_FILENAME}</a></p>"
else
  repo_key_line="<p>Repository key: <code>not configured</code></p>"
fi

cat > "${SITE_DIR}/index.html" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Haveno Reto Debian Repository</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
  <h1>Haveno Reto Debian Repository</h1>
  <p>Repository source: <a href="https://github.com/${SOURCE_OWNER}/${SOURCE_REPO}/releases">${SOURCE_OWNER}/${SOURCE_REPO} releases</a></p>
  <p>Distribution: <code>${APT_DIST}</code>, Component: <code>${APT_COMPONENT}</code></p>
  ${repo_key_line}
  <p>Generated at: <code>$(date -u +"%Y-%m-%dT%H:%M:%SZ")</code></p>
</body>
</html>
EOF

echo "Done. Repository generated under ${SITE_DIR}/"
