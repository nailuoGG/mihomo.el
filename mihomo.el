;;; mihomo.el --- Mihomo configuration and controller tools -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; URL: https://github.com/nailuoGG/mihomo.el
;; Keywords: convenience, languages, tools
;; Package-Requires: ((emacs "29.1") (transient "0.8.0") (websocket "1.12") (yaml-mode "0.0.16"))
;; Version: 0.3.0

;;; Commentary:
;; Edit Mihomo configuration files and operate the external controller from
;; Emacs.  Run `mihomo' for the controller menu.

;;; Code:

(require 'mihomo-api)
(require 'mihomo-config-mode)
(require 'mihomo-connections)
(require 'mihomo-providers)
(require 'mihomo-proxies)
(require 'mihomo-realtime)
(require 'transient)

(defun mihomo--message-result (success error)
  "Display SUCCESS or controller ERROR."
  (message "Mihomo: %s"
           (if error (mihomo-api--error-message error) success)))

;;;###autoload
(defun mihomo-status ()
  "Display the Mihomo controller version and current mode."
  (interactive)
  (mihomo-api-version
   (lambda (version error)
     (if error
         (mihomo--message-result nil error)
       (mihomo-api-configs
        (lambda (configs config-error)
          (if config-error
              (mihomo--message-result nil config-error)
            (message "Mihomo: %s %s, mode %s"
                     (if (eq (gethash "meta" version) t) "Meta" "")
                     (or (gethash "version" version) "unknown")
                     (or (gethash "mode" configs) "unknown")))))))))

;;;###autoload
(defun mihomo-set-mode (mode)
  "Set Mihomo controller MODE."
  (interactive
   (list (completing-read "Mihomo mode: " '("rule" "global" "direct")
                          nil t)))
  (mihomo-api-set-mode
   mode (lambda (_result error)
          (mihomo--message-result (format "mode changed to %s" mode) error))))

;;;###autoload
(defun mihomo-reload-config (file)
  "Reload Mihomo configuration FILE."
  (interactive
   (list (read-file-name "Mihomo configuration: "
                         (and mihomo-config-file
                              (file-name-directory mihomo-config-file))
                         mihomo-config-file t)))
  (mihomo-api-reload-config
   file (lambda (_result error)
          (mihomo--message-result
           (format "reloaded %s" (abbreviate-file-name file)) error))))

;;;###autoload
(transient-define-prefix mihomo ()
  "Operate the Mihomo external controller."
  [["Controller"
    ("s" "Status" mihomo-status)
    ("m" "Set mode" mihomo-set-mode)
    ("r" "Reload config" mihomo-reload-config)]
   ["Management"
    ("p" "Proxy groups" mihomo-proxies)
    ("c" "Connections" mihomo-connections)
    ("P" "Providers" mihomo-providers)]
   ["Realtime"
    ("l" "Logs" mihomo-logs)
    ("t" "Traffic" mihomo-traffic)]])

(provide 'mihomo)
;;; mihomo.el ends here
