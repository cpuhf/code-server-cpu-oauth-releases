# code-server-cpu-oauth releases

Public Ubuntu build downloads for code-server-cpu-oauth. The source repository
is private; this repository contains release downloads only. The archive
contains the compiled application, bundled VS Code web assets, Node.js, and
runtime dependencies.

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
