# code-server-cpu-oauth releases

Public Ubuntu build downloads for code-server-cpu-oauth. The source repository
is private; this repository contains release downloads only. The archive
contains the compiled application, bundled VS Code web assets, Node.js, and
runtime dependencies.

## Automatic Ubuntu installation

Download and run the interactive installer as your normal SSH user:

```bash
curl -fL -o install.sh https://raw.githubusercontent.com/cpuhf/code-server-cpu-oauth-releases/main/install.sh
bash install.sh
```

The [installer](install.sh) uses sudo for system changes. It supports Ubuntu
x86_64 with a working systemd user session and requires an interactive terminal.
If curl is not installed, install it first with `sudo apt-get install curl`.

It performs the following steps:

1. Detects Ubuntu version and CPU architecture, downloads the pinned release,
   verifies its SHA-256 checksum, and checks the bundled runtime.
2. Rebuilds `node-pty` on Ubuntu versions older than 26.04, or when the native
   module cannot load. It installs build tools as needed and tests Bash startup
   before replacing the existing installation.
3. Stops existing code-server user and system services for the invoking account
   and removes the `code-server` apt package if installed.
4. Moves `~/.local/share/code-server` and `~/.config/code-server` into a private
   backup directory under `~/.local/state/code-server-installer/backups/`. This
   removes old settings and extensions from their active locations. An existing
   `/opt/code-server` is moved to `/opt/code-server.backup-<timestamp>-<pid>`.
5. Prompts for your public HTTPS hostname, Google OAuth client ID, client secret,
   allowed email addresses, and local port. The secret is hidden during entry.
6. Writes `~/.config/code-server/.env` with permissions `600`, installs the
   application under `/opt/code-server`, creates and starts the systemd user
   service, enables startup after logout and at boot, and checks the HTTP service.

Keep the printed OAuth callback URL registered in your Google OAuth client.
Configure an HTTPS reverse proxy with WebSocket support to forward to the
printed `127.0.0.1:<port>` address. The installer configures code-server; your
DNS, TLS certificate, and reverse proxy need to be configured separately.

For older Ubuntu, the native-module rebuild downloads dependencies and Node.js
headers. If apt or npm reports an error, fix that error before rerunning. Other
native dependencies may still need a full build for the target Ubuntu version.
The terminal rebuild was confirmed to fix the reported Ubuntu 25.04 installation.

Rerunning the installer creates fresh configuration and moves the existing
settings and extensions to another backup. To inspect the running service:

```bash
systemctl --user --no-pager status code-server
journalctl --user -u code-server -f
```

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

Run code-server as your normal user, not root. Personal settings, extensions, and
workspaces belong to that user.

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

Run the following over SSH. First install the compiler, Python, and npm:

```bash
sudo apt-get update
sudo apt-get install -y build-essential python3 npm
```

If package installation fails, stop and resolve the package repository errors
before continuing. See the upstream [node-gyp build requirements](https://github.com/nodejs/node-gyp#on-unix).

Then run this block as the normal user who runs code-server. It downloads the
installed `node-pty` version and build tools into a temporary directory, compiles
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

npm install --prefix "$repair_dir" --ignore-scripts \
  --no-audit --no-fund "node-pty@$pty_version" node-gyp@11

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
private workspace information. Do not post `server.env`.

## Updating

Stop the service with `systemctl --user stop code-server`. Download and verify the
new release, extract it into a new empty directory, and check its version before
replacing `/opt/code-server`. Keep a copy of the previous installation until the
new version works. Start the service with `systemctl --user start code-server`.
Keep your existing `~/.config/code-server/server.env`; credentials do not belong
in the archive.
