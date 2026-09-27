# code-server-cpu-oauth releases

Public Ubuntu build downloads for code-server-cpu-oauth. The source repository
is private; this repository contains release downloads only. The archive
contains the compiled application, bundled VS Code web assets, Node.js, and
runtime dependencies.

## Download and install

The current build targets Ubuntu 26.04 on x86_64. Download the
[2026-09-27 release](https://github.com/cpuhf/code-server-cpu-oauth-releases/releases/tag/ubuntu-2026-09-27)
without a GitHub account:

```bash
curl -fL -O https://github.com/cpuhf/code-server-cpu-oauth-releases/releases/download/ubuntu-2026-09-27/code-server-ubuntu.tar.gz
echo '8a1893dccefac286318130384fb24571705336187cca12a03e2b193b55225d8f  code-server-ubuntu.tar.gz' | sha256sum -c -
mkdir -p "$HOME/apps/code-server"
tar -xzf code-server-ubuntu.tar.gz -C "$HOME/apps/code-server"
"$HOME/apps/code-server/bin/code-server" --version
```

The archive is self-contained; the server does not need Node.js, npm, or a
source checkout. Extract future releases into an empty directory before
replacing an existing installation.

## Configure authentication

Create a Google OAuth web application with
`https://your-domain/auth/google/callback` as an authorized redirect URI.
Store its credentials in a file readable only by the account running
code-server, for example `~/.config/code-server/server.env`:

```dotenv
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
GOOGLE_ALLOWED_USERS=you@example.com
GOOGLE_REDIRECT_URI=https://your-domain/auth/google/callback
CODE_SERVER_BIND_ADDR=127.0.0.1:8080
```

Start with `CODE_SERVER_ENV_FILE` pointing to that file:

```bash
CODE_SERVER_ENV_FILE="$HOME/.config/code-server/server.env" "$HOME/apps/code-server/bin/code-server"
```

Keep the credentials on the server. They are not included in the release.
