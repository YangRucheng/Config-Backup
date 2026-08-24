#! /bin/bash

set -euo pipefail

API_URL="https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
GHFAST_PREFIX="https://ghfast.top/"
ASSET_NAME="${ASSET_NAME:-}"
RESTART_DELAY_SECONDS="${RESTART_DELAY_SECONDS:-10}"
TMP_FILE=""
TMP_DIR=""
TARGET="/usr/bin/cloudflared"
UPDATE_UNITS=("cloudflared-update.service" "cloudflared-update.timer")
SERVICE_UNITS=("cloudflared@quic.service" "cloudflared@http2.service")
SERVICE_UNIT_DIR="${SERVICE_UNIT_DIR:-/etc/systemd/system}"
SERVICE_TEMPLATE_URL_BASE="${SERVICE_TEMPLATE_URL_BASE:-https://proxy.19890605.xyz/raw.githubusercontent.com/YangRucheng/Config-Backup/refs/heads/main/resource/cloudflared}"
TOKEN_PLACEHOLDER="__CLOUDFLARED_TOKEN__"

log_step() {
  echo
  echo "==> $*"
}

log_info() {
  echo "[+] $*"
}

log_warn() {
  echo "[!] $*"
}

die() {
  echo "[!] $*" >&2
  exit 1
}

require_commands() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    die "缺少依赖: ${missing[*]}"
  fi
}

cleanup() {
  case "${TMP_DIR}" in
    /tmp/cloudflared-upgrade.*)
      rm -rf -- "${TMP_DIR}"
      ;;
  esac
}

make_tmp_file() {
  local name="$1"

  if [ -z "${TMP_DIR}" ]; then
    die "临时目录尚未初始化"
  fi

  mktemp "${TMP_DIR}/${name}.XXXXXX"
}

detect_cloudflared_asset_name() {
  local machine

  machine="$(uname -m)"

  case "${machine}" in
    x86_64|amd64)
      printf '%s' "cloudflared-linux-amd64"
      ;;
    aarch64|arm64)
      printf '%s' "cloudflared-linux-arm64"
      ;;
    *)
      die "不支持的架构: ${machine}；请手动设置 ASSET_NAME=cloudflared-linux-amd64 或 ASSET_NAME=cloudflared-linux-arm64"
      ;;
  esac
}

fetch_latest_url() {
  local headers=(
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  curl -fsSL --connect-timeout 15 --retry 3 \
    "${headers[@]}" \
    "${API_URL}" \
    | awk -v asset_name="${ASSET_NAME}" '
        /^[[:space:]]*"name":[[:space:]]*"/ {
          name = $0
          sub(/^[[:space:]]*"name":[[:space:]]*"/, "", name)
          sub(/",?[[:space:]]*$/, "", name)
          matched = (name == asset_name)
        }

        matched && /^[[:space:]]*"browser_download_url":[[:space:]]*"/ {
          url = $0
          sub(/^[[:space:]]*"browser_download_url":[[:space:]]*"/, "", url)
          sub(/",?[[:space:]]*$/, "", url)
          print url
          found = 1
        }

        END {
          if (!found) {
            exit 1
          }
        }
      '
}

get_unit_fragment_path() {
  local unit="$1"

  systemctl show -p FragmentPath --value "${unit}" 2>/dev/null || true
}

unit_exists() {
  local unit="$1"
  local load_state

  load_state="$(systemctl show -p LoadState --value "${unit}" 2>/dev/null || true)"
  [ -n "${load_state}" ] && [ "${load_state}" != "not-found" ]
}

stop_unit_if_active() {
  local unit="$1"

  if systemctl is-active --quiet "${unit}"; then
    log_info "停止 ${unit}"
    systemctl stop "${unit}"
  else
    log_info "${unit} 未运行，跳过停止"
  fi
}

disable_unit_if_enabled() {
  local unit="$1"
  local enabled_state

  enabled_state="$(systemctl is-enabled "${unit}" 2>/dev/null || true)"

  case "${enabled_state}" in
    enabled|enabled-runtime|linked|linked-runtime|alias)
      log_info "禁用 ${unit}（当前状态: ${enabled_state}）"
      systemctl disable "${unit}"
      ;;
    disabled|static|indirect|generated|transient|masked)
      log_info "${unit} 无需禁用（当前状态: ${enabled_state}）"
      ;;
    not-found)
      log_info "${unit} 未安装，跳过禁用"
      ;;
    *)
      die "无法确认 ${unit} 是否已启用（当前状态: ${enabled_state:-unknown}）"
      ;;
  esac
}

remove_cloudflared_update_units() {
  local unit
  local fragment
  local path
  local unit_paths

  log_step "2/7 移除 cloudflared 自动更新 systemd 任务（如果存在）"

  for unit in "${UPDATE_UNITS[@]}"; do
    log_info "检查 ${unit}"

    if unit_exists "${unit}"; then
      stop_unit_if_active "${unit}"
      disable_unit_if_enabled "${unit}"
    else
      log_info "${unit} 未安装，跳过停止和禁用"
    fi

    fragment="$(get_unit_fragment_path "${unit}")"
    if [ -n "${fragment}" ] && [ "${fragment}" != "n/a" ] && [ -e "${fragment}" ]; then
      case "${fragment}" in
        /etc/systemd/system/*|/run/systemd/system/*|/usr/local/lib/systemd/system/*|/usr/lib/systemd/system/*|/lib/systemd/system/*)
          log_info "删除 ${fragment}"
          rm -f "${fragment}"
          ;;
        *)
          die "发现非标准 systemd 目录中的 unit 文件，无法安全移除: ${fragment}"
          ;;
      esac
    fi

    unit_paths=(
      "/etc/systemd/system/${unit}"
      "/run/systemd/system/${unit}"
      "/usr/local/lib/systemd/system/${unit}"
      "/usr/lib/systemd/system/${unit}"
      "/lib/systemd/system/${unit}"
    )

    for path in "${unit_paths[@]}"; do
      if [ -e "${path}" ]; then
        log_info "删除 ${path}"
        rm -f "${path}"
      else
        log_info "未找到 ${path}"
      fi
    done
  done

  log_info "重新加载 systemd"
  systemctl daemon-reload
  log_info "cloudflared 自动更新任务清理完成"
}

service_token_env_name() {
  local unit="$1"

  case "${unit}" in
    cloudflared@quic.service)
      printf '%s' "CLOUDFLARED_QUIC_TOKEN"
      ;;
    cloudflared@http2.service)
      printf '%s' "CLOUDFLARED_HTTP2_TOKEN"
      ;;
    *)
      printf '%s' "CLOUDFLARED_TOKEN"
      ;;
  esac
}

extract_cloudflared_token() {
  awk '
    function clean(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      sub(/\\$/, "", value)
      gsub(/^["\047]|["\047]$/, "", value)
      return value
    }

    function valid(value) {
      return value != "" && value != "\\" && value != "__CLOUDFLARED_TOKEN__" && value != "{{TOKEN}}"
    }

    {
      for (i = 1; i <= NF; i++) {
        field = clean($i)

        if (want_token) {
          if (valid(field)) {
            print field
            exit
          }

          if (field != "" && field != "\\") {
            want_token = 0
          }
        }

        if (field == "--token") {
          want_token = 1
        } else if (field ~ /^--token=/) {
          sub(/^--token=/, "", field)
          field = clean(field)
          if (valid(field)) {
            print field
            exit
          }
        } else if (field ~ /TUNNEL_TOKEN=/) {
          sub(/^.*TUNNEL_TOKEN=/, "", field)
          field = clean(field)
          if (valid(field)) {
            print field
            exit
          }
        }
      }
    }
  '
}

read_existing_service_token() {
  local unit="$1"
  local token
  local path
  local candidate_paths

  token="$({ systemctl cat "${unit}" 2>/dev/null || true; } | extract_cloudflared_token || true)"
  if [ -n "${token}" ]; then
    printf '%s' "${token}"
    return
  fi

  candidate_paths=(
    "${SERVICE_UNIT_DIR}/${unit}"
    "/etc/systemd/system/${unit}"
    "/run/systemd/system/${unit}"
    "/usr/local/lib/systemd/system/${unit}"
    "/usr/lib/systemd/system/${unit}"
    "/lib/systemd/system/${unit}"
  )

  for path in "${candidate_paths[@]}"; do
    if [ -f "${path}" ]; then
      token="$(extract_cloudflared_token < "${path}" || true)"
      if [ -n "${token}" ]; then
        printf '%s' "${token}"
        return
      fi
    fi
  done
}

prompt_for_service_token() {
  local unit="$1"
  local env_name="$2"
  local token=""

  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    die "无法读取 ${unit} 的 token，且当前没有可交互的 TTY；请设置环境变量 ${env_name} 后重试"
  fi

  while [ -z "${token}" ]; do
    printf "请输入 %s 的 cloudflared tunnel token: " "${unit}" >/dev/tty
    IFS= read -r -s token </dev/tty || die "读取 ${unit} token 失败"
    printf "\n" >/dev/tty

    if [ -z "${token}" ]; then
      printf "token 不能为空，请重试。\n" >/dev/tty
    fi
  done

  printf '%s' "${token}"
}

render_service_template() {
  local token="$1"

  awk -v token="${token}" -v placeholder="${TOKEN_PLACEHOLDER}" '
    function replace_all(value, needle,   pos) {
      while ((pos = index(value, needle)) > 0) {
        value = substr(value, 1, pos - 1) token substr(value, pos + length(needle))
      }
      return value
    }

    {
      line = replace_all($0, placeholder)
      line = replace_all(line, "{{TOKEN}}")
      print line
    }
  '
}

install_cloudflared_service_units() {
  local unit
  local env_name
  local token
  local tmp_template
  local tmp_unit
  local target_path

  log_step "3/7 同步 cloudflared systemd 服务文件"

  mkdir -p "${SERVICE_UNIT_DIR}"

  for unit in "${SERVICE_UNITS[@]}"; do
    env_name="$(service_token_env_name "${unit}")"
    token="${!env_name-}"

    if [ -n "${token}" ]; then
      log_info "${unit} 使用环境变量 ${env_name} 中的 token"
    else
      token="$(read_existing_service_token "${unit}")"

      if [ -n "${token}" ]; then
        log_info "${unit} 沿用已有服务文件中的 token"
      else
        log_warn "${unit} 未找到已有 token"
        token="$(prompt_for_service_token "${unit}" "${env_name}")"
      fi
    fi

    tmp_template="$(make_tmp_file "${unit}.template")"
    tmp_unit="$(make_tmp_file "${unit}")"

    log_info "下载模板到临时文件 ${tmp_template}"
    curl -fsSL --connect-timeout 15 --retry 3 \
      -o "${tmp_template}" \
      "${SERVICE_TEMPLATE_URL_BASE}/${unit}"

    log_info "渲染服务文件 ${tmp_unit}"
    render_service_template "${token}" < "${tmp_template}" > "${tmp_unit}"

    if grep -q "${TOKEN_PLACEHOLDER}" "${tmp_unit}" || grep -q "{{TOKEN}}" "${tmp_unit}"; then
      die "${unit} 模板渲染后仍包含 token 占位符"
    fi

    chmod 0644 "${tmp_unit}"
    target_path="${SERVICE_UNIT_DIR}/${unit}"
    log_info "更新 ${target_path}"
    mv -f "${tmp_unit}" "${target_path}"
  done

  log_info "重新加载 systemd"
  systemctl daemon-reload
  log_info "cloudflared systemd 服务文件同步完成"
}

find_cloudflared_services() {
  local unit_files
  local units

  unit_files="$(systemctl list-unit-files --type=service --no-legend --no-pager)"
  units="$(systemctl list-units --type=service --all --no-legend --no-pager)"

  {
    printf '%s\n' "${unit_files}" | awk '{print $1}'
    printf '%s\n' "${units}" | awk '{if ($1 ~ /\.service$/) print $1; else print $2}'
  } | awk '
      /^cloudflared.*\.service$/ && $0 != "cloudflared-update.service" {
        print
      }
    ' | sort -u
}

schedule_cloudflared_restart() {
  local restart_job="cloudflared-upgrade-restart-$$"
  local systemctl_bin

  systemctl_bin="$(command -v systemctl)"

  log_info "提交后台延迟重启任务: ${restart_job}"
  log_info "${RESTART_DELAY_SECONDS} 秒后重启服务: $*"

  systemd-run \
    --unit="${restart_job}" \
    --description="Restart cloudflared services after upgrade" \
    --on-active="${RESTART_DELAY_SECONDS}s" \
    "${systemctl_bin}" restart "$@"

  log_info "后台重启任务已提交；当前脚本将先退出，避免 SSH 映射中断影响重启"
}

log_step "1/7 检查运行环境"
require_commands curl awk grep systemctl systemd-run chmod mkdir mv rm mktemp sort uname
log_info "依赖检查通过"

if [ -z "${ASSET_NAME}" ]; then
  ASSET_NAME="$(detect_cloudflared_asset_name)"
  log_info "自动选择下载文件: ${ASSET_NAME}"
else
  log_info "使用指定下载文件: ${ASSET_NAME}"
fi

systemctl list-unit-files --type=service --no-legend --no-pager >/dev/null
log_info "systemd 查询检查通过"

if [ "${EUID}" -ne 0 ]; then
  die "请使用 root 权限运行"
fi
log_info "root 权限检查通过"

TMP_DIR="$(mktemp -d /tmp/cloudflared-upgrade.XXXXXX)"
trap cleanup EXIT
log_info "临时目录: ${TMP_DIR}"

TMP_FILE="$(make_tmp_file cloudflared)"
log_info "临时文件: ${TMP_FILE}"

remove_cloudflared_update_units

install_cloudflared_service_units

log_step "4/7 通过 GitHub API 获取最新 ${ASSET_NAME} 下载链接"
ORIGIN_URL="$(fetch_latest_url)" || die "无法从 GitHub API 获取 ${ASSET_NAME} 下载链接"
URL="${GHFAST_PREFIX}${ORIGIN_URL}"
log_info "原始链接: ${ORIGIN_URL}"
log_info "加速链接: ${URL}"

log_step "5/7 下载最新 cloudflared"

curl -L --fail --connect-timeout 15 --retry 3 \
  -o "${TMP_FILE}" \
  "${URL}"

log_info "下载完成: ${TMP_FILE}"
chmod +x "${TMP_FILE}"

log_step "6/7 安装二进制到 ${TARGET}"
mv -f "${TMP_FILE}" "${TARGET}"
log_info "安装完成: ${TARGET}"

log_step "7/7 启用 cloudflared 服务并提交延迟重启任务"

SERVICES_TEXT="$(find_cloudflared_services)"

if [ -n "${SERVICES_TEXT}" ]; then
  mapfile -t SERVICES <<< "${SERVICES_TEXT}"
else
  SERVICES=()
fi

if [ "${#SERVICES[@]}" -eq 0 ]; then
  log_warn "没有找到 cloudflared 开头的服务"
  exit 0
fi

log_info "发现服务: ${SERVICES[*]}"

for svc in "${SERVICES[@]}"; do
  log_info "启用 ${svc}"
  systemctl enable "${svc}"
done

schedule_cloudflared_restart "${SERVICES[@]}"

echo
log_info "完成；cloudflared 将在 ${RESTART_DELAY_SECONDS} 秒后由 systemd 后台重启"
