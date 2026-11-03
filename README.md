# mihomo.el

`mihomo.el` provides Emacs editing support for [Mihomo](https://github.com/MetaCubeX/mihomo) configuration files.

Version 0.1 includes:

- YAML editing through `yaml-mode`;
- highlighting for Mihomo rule, proxy, and proxy-group types;
- completion for common configuration keys;
- built-in configuration snippets;
- asynchronous Flymake validation through `mihomo -t`.

Controller and dashboard features are planned for later releases.

## Requirements

- Emacs 29.1 or newer;
- `yaml-mode` 0.0.16 or newer;
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
(load "/path/to/mihomo.el/test/mihomo-config-mode-test.el" nil t)
(ert-run-tests-interactively "^mihomo-")
```

## Scope

Version 0.1 does not install or launch Mihomo, manage system proxy settings, download subscriptions, or connect to the external-controller API.

## License

MIT
