;;; mihomo-config-mode.el --- Edit Mihomo configuration files -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: Liu Jiale
;; Keywords: convenience, languages, tools
;; Package-Requires: ((emacs "29.1") (yaml-mode "0.0.16"))
;; Version: 0.4.0

;;; Commentary:
;; YAML editing, completion, snippets, and Flymake integration for Mihomo
;; configuration files.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'yaml-mode)

(defgroup mihomo nil
  "Edit and operate Mihomo configurations."
  :group 'tools
  :prefix "mihomo-")

(defcustom mihomo-executable "mihomo"
  "Mihomo executable used to validate configuration files."
  :type 'file)

(defcustom mihomo-config-file-regexp
  (rx (or "mihomo" "clash") (* anychar) "." (or "yaml" "yml") string-end)
  "File name regexp used to activate `mihomo-config-mode'."
  :type 'regexp)

(defconst mihomo-config--top-level-keys
  '("allow-lan" "authentication" "bind-address" "dns"
    "external-controller" "external-controller-cors" "external-ui"
    "external-ui-url" "find-process-mode" "geodata-loader" "geox-url"
    "global-client-fingerprint" "hosts" "ipv6" "keep-alive-idle"
    "keep-alive-interval" "listeners" "log-level" "mixed-port" "mode"
    "port" "profile" "proxies" "proxy-groups" "proxy-providers"
    "redir-port" "rule-providers" "rules" "secret" "sniffer"
    "socks-port" "store-selected" "store-fake-ip" "sub-rules"
    "tcp-concurrent" "tproxy-port" "tun" "unified-delay")
  "Common top-level Mihomo configuration keys.")

(defconst mihomo-config--nested-keys
  '("name" "type" "server" "port" "cipher" "password" "uuid"
    "network" "udp" "tls" "sni" "skip-cert-verify" "client-fingerprint"
    "proxies" "use" "url" "interval" "tolerance" "lazy" "strategy"
    "path" "health-check" "behavior" "format" "payload" "proxy"
    "enable" "stack" "device" "dns-hijack" "auto-route"
    "auto-detect-interface" "default-nameserver" "nameserver" "fallback"
    "fake-ip-range" "fake-ip-filter" "nameserver-policy" "respect-rules"
    "enhanced-mode")
  "Common nested Mihomo configuration keys.")

(defconst mihomo-config--rule-types
  '("DOMAIN" "DOMAIN-SUFFIX" "DOMAIN-KEYWORD" "DOMAIN-REGEX" "GEOSITE"
    "IP-CIDR" "IP-CIDR6" "IP-SUFFIX" "GEOIP" "SRC-GEOIP" "SRC-IP-CIDR"
    "SRC-PORT" "DST-PORT" "IN-PORT" "IN-TYPE" "IN-USER" "IN-NAME"
    "PROCESS-PATH" "PROCESS-PATH-REGEX" "PROCESS-NAME"
    "PROCESS-NAME-REGEX" "NETWORK" "UID" "RULE-SET" "SUB-RULE" "MATCH")
  "Mihomo rule types highlighted in rule lists.")

(defconst mihomo-config--proxy-types
  '("direct" "reject" "ss" "ssr" "vmess" "vless" "trojan" "snell"
    "http" "socks5" "hysteria" "hysteria2" "tuic" "wireguard" "ssh")
  "Mihomo proxy types.")

(defconst mihomo-config--group-types
  '("select" "url-test" "fallback" "load-balance" "relay")
  "Mihomo proxy group types.")

(defconst mihomo-config--snippets
  '(("rule/domain" . "- DOMAIN,example.com,DIRECT")
    ("rule/domain-suffix" . "- DOMAIN-SUFFIX,example.com,Proxy")
    ("rule/ip-cidr" . "- IP-CIDR,192.0.2.0/24,DIRECT,no-resolve")
    ("rule/process-name" . "- PROCESS-NAME,example,Proxy")
    ("rule/rule-set" . "- RULE-SET,example,Proxy")
    ("proxy/ss" . "- name: Example\n  type: ss\n  server: example.com\n  port: 443\n  cipher: aes-128-gcm\n  password: change-me\n  udp: true")
    ("proxy-group/select" . "- name: Proxy\n  type: select\n  proxies:\n    - DIRECT")
    ("proxy-group/url-test" . "- name: Auto\n  type: url-test\n  proxies:\n    - DIRECT\n  url: https://www.gstatic.com/generate_204\n  interval: 300")
    ("rule-provider/http" . "example:\n  type: http\n  behavior: classical\n  format: yaml\n  url: https://example.com/rules.yaml\n  path: ./ruleset/example.yaml\n  interval: 86400"))
  "Built-in Mihomo configuration snippets.")

(defvar mihomo-config-mode-font-lock-keywords
  `((,(regexp-opt mihomo-config--rule-types 'symbols) . font-lock-builtin-face)
    (,(regexp-opt (append mihomo-config--proxy-types mihomo-config--group-types)
                  'symbols)
     . font-lock-type-face))
  "Additional font-lock keywords for `mihomo-config-mode'.")

(defun mihomo-config--key-bounds ()
  "Return completion bounds when point is in a YAML mapping key."
  (save-excursion
    (let ((end (point)))
      (skip-chars-backward "[:alnum:]_-" (line-beginning-position))
      (when (string-match-p
             (rx line-start (* blank) string-end)
             (buffer-substring-no-properties (line-beginning-position) (point)))
        (cons (point) end)))))

(defun mihomo-config-completion-at-point ()
  "Complete common Mihomo keys at point."
  (when-let* ((bounds (mihomo-config--key-bounds)))
    (list (car bounds) (cdr bounds)
          (if (= (current-indentation) 0)
              mihomo-config--top-level-keys
            mihomo-config--nested-keys)
          :exclusive 'no)))

(defun mihomo-config-insert-snippet (name)
  "Insert built-in Mihomo snippet NAME at the current indentation."
  (interactive
   (list (completing-read "Mihomo snippet: " mihomo-config--snippets nil t)))
  (let* ((template (alist-get name mihomo-config--snippets nil nil #'string=))
         (indent (make-string (current-indentation) ?\s)))
    (unless template
      (user-error "Unknown Mihomo snippet: %s" name))
    (insert (replace-regexp-in-string "\n" (concat "\n" indent) template))))

;;;###autoload
(define-derived-mode mihomo-config-mode yaml-mode "Mihomo"
  "Major mode for editing Mihomo configuration files."
  (font-lock-add-keywords nil mihomo-config-mode-font-lock-keywords 'append)
  (add-hook 'completion-at-point-functions
            #'mihomo-config-completion-at-point nil t)
  (when (require 'mihomo-flymake nil t)
    (add-hook 'flymake-diagnostic-functions #'mihomo-flymake-backend nil t)
    (flymake-mode 1)))

;;;###autoload
(add-to-list 'auto-mode-alist
             `(,mihomo-config-file-regexp . mihomo-config-mode))

;;;###autoload
(defalias 'clash-mode #'mihomo-config-mode)

(provide 'mihomo-config-mode)
;;; mihomo-config-mode.el ends here
