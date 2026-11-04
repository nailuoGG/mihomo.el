;;; mihomo-providers.el --- Mihomo provider management -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.4.0

;;; Commentary:
;; Tabulated proxy and rule provider management for Mihomo.

;;; Code:

(require 'cl-lib)
(require 'mihomo-api)
(require 'subr-x)
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

(defun mihomo-providers-show-details ()
  "Display details for the provider at point."
  (interactive)
  (pcase-let ((`(,kind . ,name) (mihomo-providers--selected)))
    (mihomo-provider-detail kind name)))

(defvar-keymap mihomo-providers-mode-map
  :doc "Keymap for `mihomo-providers-mode'."
  :parent tabulated-list-mode-map
  "RET" #'mihomo-providers-show-details
  "d" #'mihomo-providers-show-details
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

(defvar-local mihomo-provider-detail--kind nil)
(defvar-local mihomo-provider-detail--name nil)
(defvar-local mihomo-provider-detail--data nil)

(defun mihomo-provider-detail--latest-delay (proxy)
  "Return the latest delay string for PROXY."
  (when-let* ((history (gethash "history" proxy))
              (latest (car (last history)))
              (delay (gethash "delay" latest)))
    (number-to-string delay)))

(defun mihomo-provider-detail--proxy-entries (provider)
  "Return node entries for proxy PROVIDER."
  (mapcar
   (lambda (proxy)
     (let ((name (or (gethash "name" proxy) "")))
       (list name
             (vector name
                     (or (gethash "type" proxy) "")
                     (if (eq (gethash "alive" proxy) t) "yes" "no")
                     (or (mihomo-provider-detail--latest-delay proxy) "-")
                     (if (eq (gethash "udp" proxy) t) "yes" "no")))))
   (or (gethash "proxies" provider) nil)))

(defun mihomo-provider-detail--rule-entries (provider)
  "Return payload entries for rule PROVIDER when exposed by Mihomo."
  (let ((index 0))
    (mapcar
     (lambda (payload)
       (prog1 (list index (vector (number-to-string index) payload))
         (cl-incf index)))
     (or (gethash "payload" provider) nil))))

(defun mihomo-provider-detail--render (provider)
  "Render PROVIDER in the current detail buffer."
  (setq mihomo-provider-detail--data provider)
  (if (eq mihomo-provider-detail--kind 'proxy)
      (setq tabulated-list-format
            [("Node" 32 t) ("Type" 16 t) ("Alive" 7 t)
             ("Delay (ms)" 12 t) ("UDP" 6 t)]
            tabulated-list-entries
            (mihomo-provider-detail--proxy-entries provider))
    (setq tabulated-list-format [("Index" 7 t) ("Payload" 80 t)]
          tabulated-list-entries
          (mihomo-provider-detail--rule-entries provider)))
  (let* ((payload (gethash "payload" provider))
         (metadata
          (format " %s Provider: %s  vehicle: %s  updated: %s  items: %s%s"
                  (capitalize (symbol-name mihomo-provider-detail--kind))
                  mihomo-provider-detail--name
                  (or (gethash "vehicleType" provider) "")
                  (or (gethash "updatedAt" provider) "")
                  (if (eq mihomo-provider-detail--kind 'proxy)
                      (length (gethash "proxies" provider))
                    (or (gethash "ruleCount" provider) 0))
                  (if (and (eq mihomo-provider-detail--kind 'rule)
                           (null payload))
                      "  (rule payload is not exposed by the controller API)"
                    ""))))
    (tabulated-list-init-header)
    (setq header-line-format metadata))
  (tabulated-list-print t))

(defun mihomo-provider-detail-refresh ()
  "Refresh the current provider detail buffer."
  (interactive)
  (let ((buffer (current-buffer))
        (kind mihomo-provider-detail--kind)
        (name mihomo-provider-detail--name))
    (if (eq kind 'proxy)
        (mihomo-api-proxy-provider
         name
         (lambda (provider error)
           (if error
               (message "Mihomo: %s" (mihomo-api--error-message error))
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (mihomo-provider-detail--render provider))))))
      (mihomo-api-rule-providers
       (lambda (response error)
         (if error
             (message "Mihomo: %s" (mihomo-api--error-message error))
           (let ((provider (gethash name (gethash "providers" response))))
             (if (not provider)
                 (message "Mihomo: rule Provider %s no longer exists" name)
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (mihomo-provider-detail--render provider)))))))))))

(defun mihomo-provider-detail-update ()
  "Update and refresh the current provider."
  (interactive)
  (let ((buffer (current-buffer))
        (kind mihomo-provider-detail--kind)
        (name mihomo-provider-detail--name))
    (mihomo-api-update-provider
     kind name
     (lambda (_result error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (message "Mihomo: updated %s provider %s" kind name)
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (mihomo-provider-detail-refresh))))))))

(defun mihomo-provider-detail-healthcheck ()
  "Start a health check for the current proxy provider."
  (interactive)
  (unless (eq mihomo-provider-detail--kind 'proxy)
    (user-error "Health checks apply only to Mihomo proxy providers"))
  (let ((name mihomo-provider-detail--name))
    (mihomo-api-healthcheck-provider
     name
     (lambda (_result error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (message "Mihomo: started health check for %s" name))))))

(defvar-keymap mihomo-provider-detail-mode-map
  :doc "Keymap for `mihomo-provider-detail-mode'."
  :parent tabulated-list-mode-map
  "g" #'mihomo-provider-detail-refresh
  "u" #'mihomo-provider-detail-update
  "h" #'mihomo-provider-detail-healthcheck)

(define-derived-mode mihomo-provider-detail-mode tabulated-list-mode
  "Mihomo-Provider-Detail"
  "Major mode for one Mihomo Provider."
  (setq tabulated-list-padding 2
        tabulated-list-sort-key nil
        tabulated-list-use-header-line nil))

(defun mihomo-provider-detail (kind name)
  "Display details for provider NAME of KIND."
  (let ((buffer (get-buffer-create
                 (format "*Mihomo %s Provider: %s*"
                         (capitalize (symbol-name kind)) name))))
    (with-current-buffer buffer
      (mihomo-provider-detail-mode)
      (setq mihomo-provider-detail--kind kind
            mihomo-provider-detail--name name)
      (mihomo-provider-detail-refresh))
    (pop-to-buffer buffer)))

(provide 'mihomo-providers)
;;; mihomo-providers.el ends here
