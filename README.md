# code-server-cpu-oauth releases

Public Ubuntu build downloads for code-server-cpu-oauth. The source repository
is private; this repository contains release downloads only. The archive
contains the compiled application, bundled VS Code web assets, Node.js, and
runtime dependencies.

## Automatic Ubuntu and Debian installation

Download and run the interactive installer inside your Ubuntu or Debian server/container:

```bash
curl -fL -o install.sh https://raw.githubusercontent.com/cpuhf/code-server-cpu-oauth-releases/main/install.sh
bash install.sh
```

The [installer](install.sh) accepts Ubuntu and Debian x86_64 and requires an
interactive terminal and running systemd. For a normal SSH user, it uses sudo
for system changes and uses a user service when a systemd user session is
available. If the user session bus is missing (for example, in Proxmox LXC), it
automatically uses a system service running as that same user. For root, it
uses a system service and does not require sudo or a systemd user session.
If curl is missing, install it with `sudo apt-get install curl` as a normal user,
or `apt-get install curl` as root.

Installer revision `2026-09-29.1` selects the service mode automatically:

| Account / session | Service account and scope | Status and logs |
| --- | --- | --- |
| Normal user with a user session bus | Same user; user service | `systemctl --user status code-server`; `journalctl --user -u code-server -f` |
| Normal user without a user bus, with sudo | Same user; system service | `sudo systemctl status code-server`; `sudo journalctl -u code-server -f` |
| Root with `HOME=/root` | Root; system service | `systemctl status code-server`; `journalctl -u code-server -f` |

If the downloaded script still reports `No systemd user session`, check
`INSTALLER_VERSION` in your downloaded file. This immutable URL retrieves the
revision with the automatic system-service fallback:

```bash
curl -fL -o install.sh https://raw.githubusercontent.com/cpuhf/code-server-cpu-oauth-releases/f1bbba11f8f91cbe94ae2f9f3b01d9b03e005794/install.sh
bash install.sh
```

It performs the following steps:

1. Detects the distribution, system version, and CPU architecture, downloads the pinned release,
   verifies its SHA-256 checksum, and checks the bundled runtime.
2. Rebuilds `node-pty` on Ubuntu versions older than 26.04, or when the native
   module cannot load on either Ubuntu or Debian. It installs build tools as needed and tests Bash startup
   before replacing the existing installation.
3. Stops existing code-server user and system services for the invoking account
   and removes the `code-server` apt package if installed.
4. Moves `~/.local/share/code-server` and `~/.config/code-server` into a private
   backup directory under `~/.local/state/code-server-installer/backups/`. This
   removes old settings and extensions from their active locations. An existing
   `/opt/code-server` is moved to `/opt/code-server.backup-<timestamp>-<pid>`.
5. Prompts for your public HTTPS hostname, Google OAuth client ID, client secret,
   allowed email addresses, local port, and whether to enable mobile phone control
   for the iOS app (default: No). The secret is hidden during entry.
6. Writes `~/.config/code-server/.env` with permissions `600`, installs the
   application under `/opt/code-server`, creates and starts a systemd service,
   enables startup at boot (and after logout for user services), and checks the HTTP service.

Choosing **Yes** for mobile phone control writes the following to
`~/.config/code-server/.env`:

```dotenv
MOBILE_API_ENABLED=true
MOBILE_WORKSPACES_JSON=[{"id":"home","name":"Home","root":"/home"}]
```

The iOS app starts with the **Home** workspace at `/home`. Access is limited by
the service account's filesystem permissions and the configured Google account
allowlist. Choosing **No** (or pressing Enter) writes `MOBILE_API_ENABLED=false`.
To change the workspace later, edit this file and restart the appropriate service.
The deployed release must include the mobile API. To check it, request
`https://your-domain/auth/mobile/authorize` without query parameters: an enabled
endpoint returns HTTP 400 with `INVALID_AUTH_REQUEST`; a generic 401 can indicate
mobile support is disabled or absent from the deployed build.

Keep the printed OAuth callback URL registered in your Google OAuth client.
Configure an HTTPS reverse proxy with WebSocket support to forward to the
printed `127.0.0.1:<port>` address. The installer configures code-server; your
DNS, TLS certificate, and reverse proxy need to be configured separately.

For older Ubuntu and Debian systems needing a terminal-module rebuild, the
installer downloads dependencies and Node.js headers. If apt or npm reports an error, fix that error before rerunning. Other
native dependencies may still need a full build for the target Ubuntu version.
The terminal rebuild was confirmed to fix the reported Ubuntu 25.04 installation.

Debian uses the same installer command above. Compatibility is checked by
running the bundled runtime and testing the actual native terminal module;
Debian version numbers are not compared with Ubuntu version numbers. If the
module fails to load, the installer rebuilds it against Debian's libraries using
the bundled Node.js. The runtime and terminal tests run before old settings or
installations are replaced. This archive was built on Ubuntu; passing these
checks does not guarantee compatibility with every native dependency on every
Debian release. Debian support has been checked with simulated installer tests;
an end-to-end installation on Debian has not yet been verified.

Rerunning the installer creates fresh configuration and moves the existing
settings and extensions to another backup. For the normal-user service mode,
inspect the running service with these commands (system service modes use the
commands in the sections below):

```bash
systemctl --user --no-pager status code-server
journalctl --user -u code-server -f
```

### Normal-user installation without a systemd user session

If `systemctl --user` fails with `Failed to connect to bus: No medium found`
but `sudo systemctl` works, download the latest installer and run `bash install.sh`
as your normal user. It detects the missing user session and uses a system service;
you may be prompted for your sudo password during this check.

The service is installed at `/etc/systemd/system/code-server.service` with
`User=` set to your account (for example, `lunchteacher`). Settings and extensions
remain under your home directory, and your private OAuth file remains at
`~/.config/code-server/.env`. This mode uses system startup at boot and does not
require linger or a user bus. Manage it with:

```bash
sudo systemctl --no-pager status code-server
sudo journalctl -u code-server -f
sudo systemctl restart code-server
```

The installer still backs up existing settings and replaces any prior
code-server system service. Only one installation can occupy `/opt/code-server`
and the `code-server.service` system unit on this server.

### Root installation in Proxmox LXC

Run the installer from a root console or SSH session **inside the LXC container**
with `HOME=/root`, using the same download/run commands above. The container must
run systemd; the installer checks this before prompting or changing installations.
Run inside the guest rather than on the Proxmox host. A Proxmox full VM with
systemd can use the same mode. Containers without systemd need a different
startup setup.

Root mode creates `/etc/systemd/system/code-server.service`, enabled under
`multi-user.target`. OAuth settings are written to `/root/.config/code-server/.env`
with mode `600`. The service explicitly uses `/root` as its home and runs as root;
it does not use `systemctl --user`, linger, or sudo to manage its new service.
Existing root settings, extensions, and a previous system unit are backed up.
Settings belonging to other user accounts are not moved.

```bash
systemctl --no-pager status code-server
journalctl -u code-server -f
systemctl restart code-server
```

The code-server terminal and extensions will have root permissions inside the
container, including access allowed to mounted directories. Root mode has been
verified with isolated installer fixtures; a full installation in Proxmox LXC
has not yet been tested.

## Download and install

The current build targets Ubuntu 26.04 on x86_64. Use a server with the same CPU
architecture; other Linux distributions and older Ubuntu versions may require a
compatible build. Node.js, npm, and a source checkout are not needed.

### 1. Get the archive

On the server, download the [2026-09-27 release](https://github.com/cpuhf/code-server-cpu-oauth-releases/releases/tag/ubuntu-2026-09-27)
and verify its checksum. No GitHub account is required:

```bash
cd "$HOME"
curl -fL -O https://github.com/cpuhf/code-server-cpu-oauth-releases/releases/download/ubuntu-2026-09-27/code-server-ubuntu.tar.gz
echo '8a1893dccefac286318130384fb24571705336187cca12a03e2b193b55225d8f  code-server-ubuntu.tar.gz' | sha256sum -c -
```

Alternatively, copy an archive you already downloaded from your local machine,
then log in to the server. Replace the username and hostname:

```bash
scp code-server-ubuntu.tar.gz youruser@your-server:~/
ssh youruser@your-server
```

### 2. Extract and verify

Run these commands on the server as the normal user who will run code-server.
Use sudo for installation into `/opt`:

```bash
sudo install -d -m 755 /opt/code-server
sudo tar -xzf ~/code-server-ubuntu.tar.gz -C /opt/code-server
sudo chown -R root:root /opt/code-server
/opt/code-server/bin/code-server --version
```

These manual instructions use a normal user; personal settings, extensions, and
workspaces belong to that user. For root installation, use the automatic installer
and the system service instructions above.

### 3. Configure Google OAuth

Create a Google OAuth client of type **Web application**, with
`https://your-domain/auth/google/callback` as an authorized redirect URI.

Create a private configuration file on the server. For an existing installation,
edit your existing file instead of running the `install` command that creates it:

```bash
install -d -m 700 ~/.config/code-server
install -m 600 /dev/null ~/.config/code-server/server.env
nano ~/.config/code-server/server.env
```

Add the following settings, replacing the example values:

```dotenv
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
GOOGLE_ALLOWED_USERS=you@example.com
GOOGLE_REDIRECT_URI=https://your-domain/auth/google/callback
CODE_SERVER_BIND_ADDR=127.0.0.1:8080
```

`GOOGLE_ALLOWED_USERS` accepts comma-separated email addresses. Configure your
HTTPS reverse proxy to forward requests, including WebSocket connections, to
`127.0.0.1:8080`. The callback URL must exactly match the URI registered with
Google. Open `https://your-domain` after starting the service.

Keep the real credentials on the server in this private file. The release does
not include credentials.

### 4. Start automatically with systemd

While logged in as the normal user who will run code-server, create a user service:

```bash
install -d -m 700 ~/.config/systemd/user
cat > ~/.config/systemd/user/code-server.service <<EOF
[Unit]
Description=code-server
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$HOME
Environment=CODE_SERVER_ENV_FILE=$HOME/.config/code-server/server.env
ExecStart=/opt/code-server/bin/code-server
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now code-server
systemctl --user --no-pager status code-server
```

To keep it running after logout and start it automatically at boot:

```bash
sudo loginctl enable-linger "$USER"
```

View logs or restart after changing configuration:

```bash
journalctl --user -u code-server -f
systemctl --user restart code-server
```

To run it in the foreground instead of using systemd:

```bash
CODE_SERVER_ENV_FILE="$HOME/.config/code-server/server.env" /opt/code-server/bin/code-server
```

## Configuration and startup troubleshooting

- `Unknown option --auth=password`: this Google OAuth build does not accept
  upstream `auth`, `password`, or `hashed-password` settings. Back up the YAML
  and remove those entries; the installer backs up and recreates its configuration.
- Google `invalid_request` with `https://https://` in the redirect URI: set
  `GOOGLE_REDIRECT_URI` to exactly `https://your-domain/auth/google/callback`,
  register the same URI with Google, and restart the appropriate service.
  The installer accepts one optional `https://` prefix and rejects duplicate prefixes.
- `HTTP server listening on http://127.0.0.1:8080/` and
  `Authentication: Google OAuth` indicate successful startup. `Not serving HTTPS`
  is expected when your reverse proxy or Cloudflare Tunnel provides public HTTPS;
  use `http://127.0.0.1:8080` as the upstream. The custom build's `0.0.0` version
  string alone does not indicate startup failure.

Use the status, restart, and log commands for your service scope. In the manual
troubleshooting and update commands below, replace `systemctl --user` with
`sudo systemctl`, and `journalctl --user` with `sudo journalctl`, for a system
service installed by a normal user. Root system services use `systemctl` and
`journalctl` without either prefix. The native-module tests should run as the
account configured to run code-server.

## Troubleshooting a blank integrated terminal

If the editor opens but its terminal stays blank, check the service logs:

```bash
journalctl --user -u code-server -f
```

Messages such as `No ptyHost heartbeat after 6 seconds` or
`No ptyHost heartbeat after 12 seconds` indicate that VS Code's terminal host
is not responding. They do not identify the underlying cause. A missing
`vsda_bg.wasm` message concerns connection signing and, by itself, does not
establish why the terminal failed.

### 1. Restart and retry

Over SSH, restart the service:

```bash
systemctl --user restart code-server
```

This interrupts active editor connections and may interrupt terminal sessions.
Reload the browser page and open a new terminal.

### 2. Test the bundled terminal dependency

If the terminal stays blank, run this over SSH as the same normal user who runs
code-server. It uses the bundled Node.js and starts Bash without loading shell
startup files; no additional Node.js installation is needed:

```bash
/opt/code-server/lib/node <<'JS'
const pty = require('/opt/code-server/lib/vscode/node_modules/node-pty');
const timer = setTimeout(() => {
  console.error('PTY timed out');
  process.exit(1);
}, 5000);
const terminal = pty.spawn('/bin/bash',
  ['--noprofile', '--norc', '-c', 'echo PTY_OK'], {
    name: 'xterm',
    cols: 80,
    rows: 24,
    cwd: process.env.HOME,
    env: process.env
  });
terminal.onData(data => process.stdout.write(data));
terminal.onExit(event => {
  clearTimeout(timer);
  process.exit(event.exitCode);
});
JS
```

Expected output is `PTY_OK`, followed by a successful exit. This confirms that
the native terminal dependency and basic Bash startup work on this server. It
does not test VS Code's terminal host, browser connection, or shell startup files.
If it fails, preserve the complete error or timeout message for diagnosis.

### If the native terminal module cannot load

If the terminal test reports `Failed to load native module: pty.node` and ends
with `Cannot find module './prebuilds/linux-x64/pty.node'`, that last path is a
fallback. The loader tries several paths and reports only the last loading
error, so this message can hide why the bundled `build/Release/pty.node` failed.

Run these commands over SSH as the same user who runs code-server:

```bash
/opt/code-server/lib/node -e \
  "require('/opt/code-server/lib/vscode/node_modules/node-pty/build/Release/pty.node'); console.log('Native module loaded')"

ldd /opt/code-server/lib/vscode/node_modules/node-pty/build/Release/pty.node

cat /etc/os-release
uname -m
```

The direct `require` exposes the original loading error. `ldd` checks the native
module's shared library dependencies. Preserve the complete output of both
commands, along with the operating system and architecture information.

The current archive was built for Ubuntu 26.04 on x86_64. An older server may
lack a required system library version. A `GLIBC_*` or `GLIBCXX_*` version error
indicates a library compatibility problem; a missing-file error indicates that
the expected module file is absent. These checks distinguish those cases from
other loading failures. A compatible build is needed for library version
mismatches; do not replace system libraries manually to match the archive.

### Repairing a GLIBC mismatch on Ubuntu 25.04

A reported installation on Ubuntu 25.04 x86_64 failed to load the archive's
terminal module with:

```text
Error: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.42' not found
(required by /opt/code-server/lib/vscode/node_modules/node-pty/build/Release/pty.node)
```

This confirms that the bundled terminal module requires a newer GLIBC version
than that server provides. Rebuilding the same `node-pty` version on the server
can address this module's compatibility problem. The user confirmed that this
repair restored the integrated terminal on that Ubuntu 25.04 installation.

Run the following over SSH. First install the compiler and Python:

```bash
sudo apt-get update
sudo apt-get install -y build-essential python3
```

If package installation fails, stop and resolve the package repository errors
before continuing. See the upstream [node-gyp build requirements](https://github.com/nodejs/node-gyp#on-unix).

Then run this block as the normal user who runs code-server. It downloads the
installed `node-pty` version, a verified standalone npm, and build tools into a
temporary directory, compiles
against the bundled Node.js, checks that the rebuilt module loads, and backs up
the original module before replacing it. The service restart interrupts active
editor connections and may interrupt terminal sessions.

```bash
(
set -e

export PATH="/opt/code-server/lib:$PATH"
repair_dir="$(mktemp -d /tmp/code-server-pty.XXXXXX)"
pty_dir="/opt/code-server/lib/vscode/node_modules/node-pty"
pty_version="$(node -p "require('$pty_dir/package.json').version")"

# Use a pinned official npm archive, avoiding the distro npm package.
curl -fL --retry 3 -o "$repair_dir/npm.tgz" \
  https://registry.npmjs.org/npm/-/npm-11.6.2.tgz
printf '%s  %s\n' 'ee22b335fcbc95662cdf3ab8a053daf045d9cf9c6df6040d28965abb707512b2c16fa6c5eec049d34c74f78f390cebd14f697919eadb97756564d4f9eccc4954' "$repair_dir/npm.tgz" | sha512sum -c -
mkdir -p "$repair_dir/npm"
tar --no-same-owner -xzf "$repair_dir/npm.tgz" -C "$repair_dir/npm"
node "$repair_dir/npm/package/bin/npm-cli.js" install \
  --prefix "$repair_dir" --ignore-scripts --no-audit --no-fund \
  --cache "$repair_dir/npm-cache" --userconfig /dev/null --registry https://registry.npmjs.org \
  "node-pty@$pty_version" node-gyp@11

cd "$repair_dir/node_modules/node-pty"
node "$repair_dir/node_modules/node-gyp/bin/node-gyp.js" rebuild

node -e \
  "require('./build/Release/pty.node'); console.log('Rebuilt module loaded')"

sudo cp -a "$pty_dir/build/Release/pty.node" \
  "$pty_dir/build/Release/pty.node.backup-$(date +%Y%m%d-%H%M%S)"

systemctl --user stop code-server
sudo install -m 755 build/Release/pty.node \
  "$pty_dir/build/Release/pty.node"
systemctl --user start code-server
)
```

Expected verification output includes `Rebuilt module loaded`. Reload the
browser and open a new terminal. You can also rerun the `PTY_OK` test above to
verify that the installed module can start Bash.

If the rebuild fails before the service stops, the installed module remains
unchanged. If replacement fails after stopping the service, run
`systemctl --user start code-server` to bring it back up and preserve the error
output for diagnosis.

This repairs only the terminal dependency. Other bundled native modules may
also require newer system libraries. A full archive built for the target
Ubuntu version and CPU architecture is the broader compatibility fix. A future
archive installation may overwrite this local repair.

### Ubuntu npm package dependency conflicts

An earlier installer attempted to install npm through apt. On a reported Ubuntu
25.04 system this failed with `node-css-loader : Depends: webpack but it is not
installable`. That error occurred before the old code-server installation or
settings were replaced.

The updated installer installs only the compiler and Python through apt. It
downloads the official npm 11.6.2 archive, verifies a pinned SHA-512 checksum, and
runs npm with the bundled Node.js in a temporary directory. It does not require
the Ubuntu or Debian npm package and does not replace system Node.js or npm.

Download the latest installer again and rerun it if you encountered this error.
If apt still fails while installing the compiler or Python, resolve that package
error before rerunning; the standalone npm only avoids npm's distro dependencies.

### 3. Collect terminal host logs

After reproducing the blank terminal, run:

```bash
find ~/.local/share/code-server -type f -iname '*ptyhost*.log' \
  -print -exec tail -n 80 {} \;

journalctl --user -u code-server --since '10 minutes ago' --no-pager
```

The file search assumes the default user data location. If you configured a
custom user data directory, search that directory instead. If no terminal host
log is found, include that fact along with the service logs.

For a debugging report, include the bundled code-server version, Ubuntu version,
CPU architecture, terminal test output, and relevant log excerpts:

```bash
/opt/code-server/bin/code-server --version
cat /etc/os-release
uname -m
```

Review logs before posting them publicly and remove credentials, tokens, and
private workspace information. Do not post `.env` or `server.env`.

## Updating

Stop the service with `systemctl --user stop code-server`. Download and verify the
new release, extract it into a new empty directory, and check its version before
replacing `/opt/code-server`. Keep a copy of the previous installation until the
new version works. Start the service with `systemctl --user start code-server`.
Keep your existing `~/.config/code-server/.env` (automatic installer) or
`~/.config/code-server/server.env` (manual setup); credentials do not belong in
the archive. Rerunning the interactive installer instead creates fresh
configuration and backs up the previous settings and extensions.
