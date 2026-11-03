;;; mihomo-providers.el --- Mihomo provider management -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.3.0

;;; Commentary:
;; Tabulated proxy and rule provider management for Mihomo.

;;; Code:

(require 'mihomo-api)
(require 'tabulated-list)

(defun mihomo-providers--entries (kind response)
  "Return provider entries of KIND from RESPONSE."
  (let ((providers (gethash "providers" response)) entries)
    (when (hash-table-p providers)
      (maphash
       (lambda (name provider)
         (let* ((vehicle (or (gethash "vehicleType" provider) ""))
                (count (if (eq kind 'proxy)
                           (length (gethash "proxies" provider))
                         (or (gethash "ruleCount" provider) 0))))
           (unless (and (eq kind 'proxy) (string= vehicle "Compatible"))
             (push (list (cons kind name)
                         (vector (capitalize (symbol-name kind))
                                 name
                                 (or (gethash "type" provider) "")
                                 vehicle
                                 (or (gethash "updatedAt" provider) "")
                                 (number-to-string count)))
                   entries))))
       providers))
    entries))

(defun mihomo-providers-refresh ()
  "Refresh the Mihomo provider buffer."
  (interactive)
  (let ((buffer (current-buffer)))
    (mihomo-api-proxy-providers
     (lambda (proxy-response proxy-error)
       (if proxy-error
           (message "Mihomo: %s" (mihomo-api--error-message proxy-error))
         (mihomo-api-rule-providers
          (lambda (rule-response rule-error)
            (if rule-error
                (message "Mihomo: %s"
                         (mihomo-api--error-message rule-error))
              (when (buffer-live-p buffer)
                (with-current-buffer buffer
                  (setq tabulated-list-entries
                        (append
                         (mihomo-providers--entries 'proxy proxy-response)
                         (mihomo-providers--entries 'rule rule-response)))
                  (tabulated-list-print t)))))))))))

(defun mihomo-providers--selected ()
  "Return the selected provider identifier."
  (or (tabulated-list-get-id)
      (user-error "No Mihomo provider on this line")))

(defun mihomo-providers-update ()
  "Update the provider at point."
  (interactive)
  (pcase-let* ((buffer (current-buffer))
               (`(,kind . ,name) (mihomo-providers--selected)))
    (mihomo-api-update-provider
     kind name
     (lambda (_result error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (message "Mihomo: updated %s provider %s" kind name)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (mihomo-providers-refresh))))))))

(defun mihomo-providers-healthcheck ()
  "Start a health check for the proxy provider at point."
  (interactive)
  (pcase-let ((`(,kind . ,name) (mihomo-providers--selected)))
    (unless (eq kind 'proxy)
      (user-error "Health checks apply only to Mihomo proxy providers"))
    (mihomo-api-healthcheck-provider
     name
     (lambda (_result error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (message "Mihomo: started health check for %s" name))))))

(defvar-keymap mihomo-providers-mode-map
  :doc "Keymap for `mihomo-providers-mode'."
  :parent tabulated-list-mode-map
  "u" #'mihomo-providers-update
  "h" #'mihomo-providers-healthcheck
  "g" #'mihomo-providers-refresh)

(define-derived-mode mihomo-providers-mode tabulated-list-mode
  "Mihomo-Providers"
  "Major mode for Mihomo providers."
  (setq tabulated-list-format
        [("Kind" 8 t)
         ("Name" 28 t)
         ("Type" 14 t)
         ("Vehicle" 12 t)
         ("Updated" 25 t)
         ("Items" 8 t)]
        tabulated-list-padding 2
        tabulated-list-sort-key '("Name" . nil))
  (tabulated-list-init-header))

;;;###autoload
(defun mihomo-providers ()
  "Display Mihomo proxy and rule providers."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Providers*")))
    (with-current-buffer buffer
      (mihomo-providers-mode)
      (mihomo-providers-refresh))
    (pop-to-buffer buffer)))

(provide 'mihomo-providers)
;;; mihomo-providers.el ends here
