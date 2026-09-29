#!/usr/bin/env bash
# Install the public x86_64 release on Ubuntu or Debian with a user or system service.
set -Eeuo pipefail

INSTALLER_VERSION="2026-09-29.1"
RELEASE_TAG="ubuntu-2026-09-27"
RELEASE_SHA256="8a1893dccefac286318130384fb24571705336187cca12a03e2b193b55225d8f"
RELEASE_URL="https://github.com/cpuhf/code-server-cpu-oauth-releases/releases/download/$RELEASE_TAG/code-server-ubuntu.tar.gz"
INSTALL_DIR="/opt/code-server"

root_mode=false
service_scope=user

as_root() {
  if [[ "$root_mode" == true ]]; then "$@"; else sudo "$@"; fi
}
service_ctl() {
  if [[ "$service_scope" == system ]]; then as_root systemctl "$@"; else systemctl --user "$@"; fi
}
service_logs() {
  if [[ "$service_scope" == system ]]; then as_root journalctl -u code-server "$@"; else journalctl --user -u code-server "$@"; fi
}

log() { printf '\n%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

select_service_mode() {
  if [[ "$root_mode" == true ]]; then
    service_scope=system
    as_root systemctl show-environment >/dev/null || die 'A running systemd system manager is required.'
  elif systemctl --user show-environment >/dev/null 2>&1; then
    service_scope=user
  else
    service_scope=system
    log 'No systemd user session; using a system service running as your account.'
    as_root systemctl show-environment >/dev/null || die 'A running systemd system manager is required for the system service fallback.'
  fi
  if [[ "$service_scope" == system ]]; then
    [[ "$HOME" == /* && "$HOME" != *[[:cntrl:]]* && "$HOME" != *[[:space:]] ]] || die 'System service requires an absolute home path without control characters or trailing whitespace.'
    service_file=/etc/systemd/system/code-server.service
  else
    service_file="$HOME/.config/systemd/user/code-server.service"
  fi
}

# Quote systemd directive values, including literal percent signs (specifiers).
systemd_value() {
  local value="$1"
  [[ "$value" != *[[:cntrl:]]* ]] || die 'Systemd settings cannot contain control characters.'
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//%/%%}"
  printf '"%s"' "$value"
}

supported_os() { [[ "$1" == ubuntu || "$1" == debian ]]; }

valid_domain() {
  [[ "$1" =~ ^([[:alnum:]]([[:alnum:]-]*[[:alnum:]])?\.)+[[:alpha:]]{2,}(:[0-9]{1,5})?$ ]]
}
valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
valid_users() {
  local address
  local -a addresses
  [[ -n "$1" && "$1" != *, && "$1" != ,* && "$1" != *,,* ]] || return 1
  IFS=',' read -r -a addresses <<< "$1"
  for address in "${addresses[@]}"; do
    [[ "$address" =~ ^[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}$ ]] || return 1
  done
}

prompt_settings() {
  local input
  while :; do
    printf 'Public HTTPS hostname (e.g. vscode.example.com): ' >&3
    IFS= read -r input <&3 || die 'Input ended.'
    input="${input#https://}"
    input="${input%/}"
    if valid_domain "$input"; then
      if [[ "$input" == *:* ]] && ! valid_port "${input##*:}"; then
        printf 'Invalid HTTPS port.\n' >&3
        continue
      fi
      public_domain="$input"
      break
    fi
    printf 'Enter a hostname, optionally with https://; do not include a path.\n' >&3
  done
  while :; do
    printf 'Google OAuth client ID: ' >&3
    IFS= read -r client_id <&3 || die 'Input ended.'
    [[ "$client_id" =~ ^[[:alnum:]_.-]+\.apps\.googleusercontent\.com$ ]] && break
    printf 'Enter the full client ID ending in .apps.googleusercontent.com.\n' >&3
  done
  while :; do
    printf 'Google OAuth client secret (hidden): ' >&3
    IFS= read -rs client_secret <&3 || die 'Input ended.'
    printf '\n' >&3
    [[ "$client_secret" =~ ^[[:alnum:]_-]+$ ]] && break
    printf 'Enter the Google-issued secret (letters, digits, underscore, or hyphen).\n' >&3
  done
  while :; do
    printf 'Allowed Google email addresses (comma-separated): ' >&3
    IFS= read -r allowed_users <&3 || die 'Input ended.'
    allowed_users="${allowed_users//[[:space:]]/}"
    valid_users "$allowed_users" && break
    printf 'Enter at least one valid email address.\n' >&3
  done
  while :; do
    printf 'Local server port [8080]: ' >&3
    IFS= read -r bind_port <&3 || die 'Input ended.'
    bind_port="${bind_port:-8080}"
    valid_port "$bind_port" && break
    printf 'Enter a port between 1 and 65535.\n' >&3
  done
  bind_port="$((10#$bind_port))"
  while :; do
    printf 'Enable mobile phone control (iOS app), with /home as the default project path? [y/N]: ' >&3
    IFS= read -r input <&3 || die 'Input ended.'
    case "$input" in
      [yY]|[yY][eE][sS]) mobile_enabled=true; break ;;
      ''|[nN]|[nN][oO]) mobile_enabled=false; break ;;
      *) printf 'Enter yes or no.\n' >&3 ;;
    esac
  done
  if [[ "$mobile_enabled" == true ]]; then
    [[ -d /home ]] || die 'Mobile access requires the default project directory /home to exist.'
  fi
  log "Register this exact Google OAuth redirect URI: https://$public_domain/auth/google/callback"
}

write_env() {
  local destination="$1"
  # Inputs are validated to exclude quotes, newlines, and dotenv metacharacters.
  (
    umask 077
    printf "GOOGLE_CLIENT_ID='%s'\nGOOGLE_CLIENT_SECRET='%s'\nGOOGLE_ALLOWED_USERS='%s'\nGOOGLE_REDIRECT_URI='https://%s/auth/google/callback'\nCODE_SERVER_BIND_ADDR='127.0.0.1:%s'\n" \
      "$client_id" "$client_secret" "$allowed_users" "$public_domain" "$bind_port" > "$destination"
    printf 'MOBILE_API_ENABLED=%s\n' "$mobile_enabled" >> "$destination"
    if [[ "$mobile_enabled" == true ]]; then
      printf '%s\n' 'MOBILE_WORKSPACES_JSON=[{"id":"home","name":"Home","root":"/home"}]' >> "$destination"
    fi
  )
  chmod 600 "$destination"
}

pty_test() {
  local root="$1"
  "$root/lib/node" - "$root/lib/vscode/node_modules/node-pty" <<'JS'
const pty = require(process.argv[2]);
let output = '';
const timer = setTimeout(() => {
  console.error('PTY test timed out');
  process.exit(1);
}, 5000);
const terminal = pty.spawn('/bin/bash', ['--noprofile', '--norc', '-c', 'echo PTY_OK'], {
  name: 'xterm', cols: 80, rows: 24, cwd: process.env.HOME, env: process.env
});
terminal.onData(data => { output += data; });
terminal.onExit(event => {
  clearTimeout(timer);
  if (event.exitCode !== 0 || !output.includes('PTY_OK')) {
    console.error('PTY test failed', event, output);
    process.exit(1);
  }
  console.log('PTY_OK');
});
JS
}

bootstrap_npm() {
  # Use the official self-contained npm package, not the distro's npm package.
  local npm_version="11.6.2"
  local npm_sha512="ee22b335fcbc95662cdf3ab8a053daf045d9cf9c6df6040d28965abb707512b2c16fa6c5eec049d34c74f78f390cebd14f697919eadb97756564d4f9eccc4954"
  local npm_archive="$work_dir/npm.tgz"
  local npm_home="$work_dir/npm"
  log "Downloading verified standalone npm $npm_version for the bundled Node.js..."
  curl --fail --location --retry 3 --output "$npm_archive" \
    "https://registry.npmjs.org/npm/-/npm-$npm_version.tgz"
  printf '%s  %s\n' "$npm_sha512" "$npm_archive" | sha512sum -c -
  mkdir -p "$npm_home"
  tar --no-same-owner -xzf "$npm_archive" -C "$npm_home"
  npm_cli="$npm_home/package/bin/npm-cli.js"
  "$stage/lib/node" "$npm_cli" --version
}

rebuild_pty() {
  log 'Building the terminal module against this server’s libraries...'
  as_root apt-get update
  as_root apt-get install -y build-essential python3
  local npm_cli
  bootstrap_npm
  (
    export PATH="$stage/lib:$PATH"
    local pty_version
    pty_version="$(node -p 'require(process.argv[1]).version' "$stage/lib/vscode/node_modules/node-pty/package.json")"
    node "$npm_cli" install --prefix "$work_dir/repair" --ignore-scripts --no-audit --no-fund \
      --cache "$work_dir/npm-cache" --userconfig /dev/null --registry https://registry.npmjs.org \
      "node-pty@$pty_version" node-gyp@11
    cd "$work_dir/repair/node_modules/node-pty"
    node "$work_dir/repair/node_modules/node-gyp/bin/node-gyp.js" rebuild
    node -e "require('./build/Release/pty.node'); console.log('Rebuilt module loaded')"
    install -m 755 build/Release/pty.node "$stage/lib/vscode/node_modules/node-pty/build/Release/pty.node"
  )
}

prepare_terminal() {
  # Ubuntu version numbers and Debian version numbers are not comparable.
  # Debian rebuilds when its actual native-module load check fails.
  if [[ "$ID" == ubuntu ]] && dpkg --compare-versions "$VERSION_ID" lt 26.04; then
    log 'Older Ubuntu detected: rebuilding node-pty for this system.'
    rebuild_pty
  elif ! "$stage/lib/node" -e 'require(process.argv[1])' "$stage/lib/vscode/node_modules/node-pty/build/Release/pty.node"; then
    rebuild_pty
  fi
  pty_test "$stage"
}

stop_old_services() {
  local unit
  if systemctl --user cat code-server.service >/dev/null 2>&1; then
    systemctl --user disable --now code-server.service
  fi
  for unit in code-server.service "code-server@$install_user.service"; do
    if [[ "$(systemctl show "$unit" -p LoadState --value)" != not-found ]]; then
      as_root systemctl stop "$unit"
      as_root systemctl disable "$unit" || log "Could not disable $unit; check this old service manually."
    fi
  done
}

replace_old_installation() {
  local source name package_status
  stop_old_services
  package_status="$(dpkg-query -W -f='${Status}' code-server 2>/dev/null || true)"
  if [[ "$package_status" == 'install ok installed' ]]; then
    as_root apt-get remove -y code-server
  fi
  install -d -m 700 "$backup_dir"
  for source in "$HOME/.local/share/code-server" "$HOME/.config/code-server"; do
    if [[ -e "$source" || -L "$source" ]]; then
      case "$source" in
        "$HOME/.local/share/code-server") name=user-data ;;
        *) name=config ;;
      esac
      mv -- "$source" "$backup_dir/$name"
    fi
  done
  if [[ -e "$HOME/.config/systemd/user/code-server.service" || -L "$HOME/.config/systemd/user/code-server.service" ]]; then
    mv -- "$HOME/.config/systemd/user/code-server.service" "$backup_dir/code-server.service"
  fi
  if [[ "$service_scope" == system ]]; then
    if as_root test -e "$service_file" || as_root test -L "$service_file"; then
      as_root mv -- "$service_file" "$backup_dir/system-code-server.service"
    fi
  fi
  if as_root test -e "$INSTALL_DIR" || as_root test -L "$INSTALL_DIR"; then
    as_root mv -- "$INSTALL_DIR" "$install_backup"
  fi
  as_root install -d -m 755 "$INSTALL_DIR"
  as_root cp -a "$stage/." "$INSTALL_DIR/"
  as_root chown -R root:root "$INSTALL_DIR"
}

configure_service() {
  service_file="${service_file:-$HOME/.config/systemd/user/code-server.service}"
  install -d -m 700 "$HOME/.config/code-server"
  install -m 600 "$work_dir/settings.env" "$HOME/.config/code-server/.env"
  cat > "$HOME/.config/code-server/config.yaml" <<'YAML'
bind-addr: 127.0.0.1:8080
cert: false
YAML
  chmod 600 "$HOME/.config/code-server/config.yaml"
  if [[ "$service_scope" == system ]]; then
    cat > "$work_dir/system-code-server.service" <<UNIT
[Unit]
Description=code-server with Google OAuth
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$install_user
WorkingDirectory=${HOME//%/%%}
Environment=$(systemd_value "HOME=$HOME")
Environment=$(systemd_value "CODE_SERVER_ENV_FILE=$HOME/.config/code-server/.env")
Environment=$(systemd_value "CODE_SERVER_CONFIG=$HOME/.config/code-server/config.yaml")
ExecStart=/opt/code-server/bin/code-server
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
    as_root install -d -m 755 "$(dirname "$service_file")"
    as_root install -m 644 "$work_dir/system-code-server.service" "$service_file"
  else
    install -d -m 700 "$HOME/.config/systemd/user"
    cat > "$service_file" <<'UNIT'
[Unit]
Description=code-server with Google OAuth
After=network-online.target

[Service]
Type=simple
WorkingDirectory=%h
Environment="CODE_SERVER_ENV_FILE=%h/.config/code-server/.env"
ExecStart=/opt/code-server/bin/code-server
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
UNIT
  fi
  if [[ "$service_scope" == user ]]; then chmod 644 "$service_file"; fi
  service_ctl daemon-reload
  if [[ "$service_scope" == user ]]; then as_root loginctl enable-linger "$install_user"; fi
  service_ctl enable --now code-server.service
}

main() {
  [[ $# == 0 ]] || die 'Usage: bash install.sh (interactive; no arguments).'
  [[ -n "$HOME" && "$HOME" != / && -d "$HOME" ]] || die 'Invalid user home directory.'
  command -v systemctl >/dev/null || die 'systemd is required.'
  if [[ $EUID == 0 ]]; then
    root_mode=true
    [[ "$HOME" == /root ]] || die 'Run root installation with HOME=/root (for example, log in directly as root).'
  else
    command -v sudo >/dev/null || die 'sudo is required for installation as a normal user.'
    [[ "$HOME" != /root ]] || die 'Invalid user home directory.'
  fi
  [[ -r /etc/os-release ]] || die 'Cannot identify the operating system.'
  # shellcheck disable=SC1091
  . /etc/os-release
  supported_os "${ID:-unknown}" || die "This installer supports Ubuntu and Debian, not ${ID:-unknown}."
  VERSION_ID="${VERSION_ID:-unknown}"
  [[ "$(uname -m)" == x86_64 ]] || die 'This release supports x86_64 only.'
  install_user="$(id -un)"
  select_service_mode
  local run_id
  run_id="$(date +%Y%m%d-%H%M%S)-$$"
  backup_dir="$HOME/.local/state/code-server-installer/backups/$run_id"
  install_backup="/opt/code-server.backup-$run_id"
  log "Installer $INSTALLER_VERSION"
  log "Detected ${PRETTY_NAME:-$ID $VERSION_ID} ($(uname -m)); installing $RELEASE_TAG for $install_user."
  log 'Existing code-server settings and extensions will be removed from their active locations and backed up. The apt package will be removed if installed.'
  exec 3<>/dev/tty || die 'An interactive terminal is required for OAuth settings.'
  prompt_settings
  exec 3>&-
  if [[ "$root_mode" != true ]]; then sudo -v; fi
  if ! command -v curl >/dev/null; then
    as_root apt-get update
    as_root apt-get install -y curl ca-certificates
  fi
  work_dir="$(mktemp -d /tmp/code-server-install.XXXXXX)"
  trap 'rm -rf -- "$work_dir"' EXIT
  trap 'printf "Installation failed. Check the error above. Backups, if created: %s and %s\n" "$backup_dir" "$install_backup" >&2' ERR
  stage="$work_dir/release"
  mkdir -p "$stage"
  write_env "$work_dir/settings.env"
  unset client_secret
  log 'Downloading and verifying the release...'
  curl --fail --location --retry 3 --output "$work_dir/code-server-ubuntu.tar.gz" "$RELEASE_URL"
  printf '%s  %s\n' "$RELEASE_SHA256" "$work_dir/code-server-ubuntu.tar.gz" | sha256sum -c -
  tar --no-same-owner -xzf "$work_dir/code-server-ubuntu.tar.gz" -C "$stage"
  [[ -x "$stage/bin/code-server" && -x "$stage/lib/node" ]] || die 'The archive is missing executable runtime files.'
  (
    unset CODE_SERVER_ENV_FILE CODE_SERVER_CONFIG
    "$stage/bin/code-server" --config "$work_dir/probe.yaml" --version
  )
  prepare_terminal
  log 'Replacing the old installation and configuring the service...'
  replace_old_installation
  configure_service
  local attempt status
  for attempt in {1..15}; do
    status="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 2 "http://127.0.0.1:$bind_port/" || true)"
    if service_ctl is-active --quiet code-server.service && [[ "$status" =~ ^(200|302|303|307|308)$ ]]; then
      log "Installed successfully. Open https://$public_domain after configuring your HTTPS reverse proxy."
      log "Forward HTTPS and WebSocket requests to 127.0.0.1:$bind_port."
      log "OAuth callback: https://$public_domain/auth/google/callback"
      log "Private environment file: $HOME/.config/code-server/.env"
      if [[ "$mobile_enabled" == true ]]; then
        log 'Mobile phone control enabled. Default project path: /home (subject to the service account permissions).'
      else
        log 'Mobile phone control disabled.'
      fi
      log "Old user data/config backup: $backup_dir"
      log "Old /opt installation backup (if present): $install_backup"
      if [[ "$service_scope" == system ]]; then
        if [[ "$root_mode" == true ]]; then
          log 'Service: systemctl status code-server; logs: journalctl -u code-server -f'
        else
          log 'Service: sudo systemctl status code-server; logs: sudo journalctl -u code-server -f'
        fi
      else
        log 'Service: systemctl --user status code-server; logs: journalctl --user -u code-server -f'
      fi
      return
    fi
    sleep 1
  done
  service_logs -n 40 --no-pager
  die 'The service did not pass the startup check. See the logs above.'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
