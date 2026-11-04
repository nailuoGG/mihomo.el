# mihomo.el

`mihomo.el` provides Emacs editing support for [Mihomo](https://github.com/MetaCubeX/mihomo) configuration files.

Version 0.5 includes:

- YAML editing through `yaml-mode`;
- highlighting, key completion, and built-in configuration snippets;
- asynchronous Flymake validation through `mihomo -t`;
- an asynchronous external-controller API client with auth-source support;
- a transient controller menu;
- proxy group selection and delay tests;
- active connection inspection and closing;
- realtime structured logs and traffic statistics;
- proxy and rule Provider inspection, details, and updates;
- paginated and filterable active rule browsing;
- local and subscribed configuration profiles with safe updates and switching.

## Requirements

- Emacs 29.1 or newer;
- `yaml-mode` 0.0.16 or newer;
- `transient` 0.8.0 or newer;
- `websocket` 1.12 or newer;
- Mihomo in `PATH`, or an explicit `mihomo-executable`, for validation.

Editing and completion continue to work when Mihomo is unavailable.

## Installation with Elpaca

```elisp
(use-package mihomo
  :ensure (:host github :repo "nailuoGG/mihomo.el"
           :files ("*.el"))
  :mode (("mihomo.*\\.ya?ml\\'" . mihomo-config-mode)
         ("clash.*\\.ya?ml\\'" . mihomo-config-mode)))
```

For a configuration named only `config.yaml`, add its exact path:

```elisp
(add-to-list 'auto-mode-alist
             `(,(rx "/.config/mihomo/config.yaml" string-end)
               . mihomo-config-mode))
```

For local development:

```elisp
(use-package mihomo
  :ensure (:repo "/path/to/mihomo.el")
  :load-path "/path/to/mihomo.el")
```

## Editing

Use `M-x mihomo-config-mode` in a Mihomo YAML buffer. Completion is available through the normal `completion-at-point` command (`M-TAB` in many configurations).

Insert a template with:

```text
M-x mihomo-config-insert-snippet
```

The initial snippets cover common rules, Shadowsocks proxies, select/url-test groups, and HTTP rule providers.

## Controller

Set the controller URL, then run `M-x mihomo`:

```elisp
(setq mihomo-controller-url "http://127.0.0.1:9090"
      mihomo-config-file "~/.config/mihomo/config.yaml")
```

The transient menu provides status, mode changes, configuration reload, proxy
groups, active connections, Providers, active rules, realtime logs, and
realtime traffic. Controller requests are asynchronous.

Store the controller secret in auth-source using the controller host and port
with the user `mihomo`. For example, the equivalent `~/.authinfo.gpg` entry is:

```text
machine 127.0.0.1 port 9090 login mihomo password YOUR_SECRET
```

Do not put the secret in Emacs configuration or customize variables.

### Proxy groups

`M-x mihomo-proxies` opens the proxy group table:

- `RET` or `s`: select a node in the group at point;
- `d`: test the group at point;
- `D`: choose any proxy or group to test;
- `g`: refresh.

### Connections

`M-x mihomo-connections` opens the active connection table:

- `k`: close the connection at point;
- `K`: confirm and close all connections;
- `g`: refresh.

### Providers

`M-x mihomo-providers` opens proxy and rule Providers in one table:

- `RET` or `d`: open Provider details;
- `u`: update the Provider at point;
- `h`: start a health check for a proxy Provider;
- `g`: refresh both Provider types.

Proxy Provider details show nodes, type, alive status, latest delay, and UDP
support. Inline Rule Provider details show their payload. Mihomo does not expose
the payload of File or HTTP Rule Providers through the controller API, so their
details show metadata and an explicit notice instead.

### Rules

`M-x mihomo-rules` opens the active rule table:

- `n` / `p`: next or previous page;
- `f`: filter by rule type, payload, or target;
- `c`: clear the filter;
- `g`: refresh.

The page size is controlled by `mihomo-rules-page-size` and defaults to 200.

### Profiles

`M-x mihomo-profiles-ui` opens the profile table:

- `u`: update a Subscription profile from its URL;
- `a`: validate and activate the profile on the running controller;
- `o`: open the profile configuration file;
- `g`: refresh.

Declare profiles in Emacs configuration:

```elisp
(setq mihomo-profiles
      '((:name "Local"
         :file "~/.config/mihomo/config.yaml")
        (:name "Subscription"
         :file "~/.config/mihomo/profiles/sub.yaml"
         :url "https://example.com/config.yaml")))
```

Subscribed configurations are downloaded to a temporary file, validated with
`mihomo -t`, and only then replace the profile file atomically. Invalid or
oversized downloads never overwrite an existing configuration. Responses larger
than `mihomo-profile-max-download-size` (default 10 MiB) are rejected. Only
HTTP and HTTPS subscription URLs are accepted.

Proxy Provider subscriptions are managed through the Providers view instead;
see `M-x mihomo-providers`.

### Realtime logs

`M-x mihomo-logs` opens a structured WebSocket log stream:

- `p`: pause or resume insertion;
- `c`: clear retained logs;
- `l`: select the minimum log level and reconnect;
- `g`: reconnect.

The buffer retains at most `mihomo-log-max-lines` lines. Closing the buffer
closes its WebSocket.

### Realtime traffic

`M-x mihomo-traffic` shows current upload/download rates and cumulative byte
counts. It updates from Mihomo once per second. Press `g` to reconnect; closing
the buffer closes its WebSocket.

## Validation

`mihomo-config-mode` enables Flymake and validates the current buffer asynchronously with:

```sh
mihomo -t -f <temporary-config>
```

The temporary file is created beside the source file so relative provider paths retain the same base directory. It is removed after each check.

If the executable is not in `PATH`:

```elisp
(setq mihomo-executable "/absolute/path/to/mihomo")
```

Inspect diagnostics with `M-x flymake-show-buffer-diagnostics`.

## Release verification

The release verifier downloads the pinned Mihomo `v1.19.33` Darwin arm64
binary, verifies its SHA-256 digest, checks the valid fixture, and confirms that
Mihomo rejects an intentionally invalid YAML file:

```sh
./scripts/verify-mihomo.sh
```

To use an archive that was downloaded separately, pass its path. The same
pinned SHA-256 check still applies:

```sh
./scripts/verify-mihomo.sh ~/Downloads/mihomo-darwin-arm64-v1.19.33.gz
```

The binary is extracted to a private temporary directory and removed when the
script exits. The script does not install or start Mihomo.

## Running tests

Load the package and test file in Emacs, then run the tests matching `^mihomo-`:

```elisp
(add-to-list 'load-path "/path/to/mihomo.el")
(mapc (lambda (file) (load file nil t))
      (directory-files "/path/to/mihomo.el/test" t "-test\\.el\\'"))
(ert-run-tests-interactively "^mihomo-")
```

## Scope

Version 0.5 does not install or launch Mihomo, manage system proxy settings,
edit active rules, expose File/HTTP Rule Provider payloads unavailable from
Mihomo, automatically activate updated subscriptions, render traffic graphs, or
manage Mihomo processes.

## License

[GPL-3.0-or-later](LICENSE)
