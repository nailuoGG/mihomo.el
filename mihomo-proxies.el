;;; mihomo-proxies.el --- Mihomo proxy group interface -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.4.0

;;; Commentary:
;; Tabulated proxy group management for the Mihomo controller.

;;; Code:

(require 'mihomo-api)
(require 'tabulated-list)

(defvar-local mihomo-proxies--data nil)

(defun mihomo-proxies--entries (response)
  "Return tabulated entries from proxy RESPONSE."
  (let ((proxies (gethash "proxies" response))
        entries)
    (when (hash-table-p proxies)
      (maphash
       (lambda (name proxy)
         (let ((candidates (gethash "all" proxy)))
           (when (consp candidates)
             (push (list name
                         (vector name
                                 (or (gethash "type" proxy) "")
                                 (or (gethash "now" proxy) "")
                                 (number-to-string (length candidates))))
                   entries))))
       proxies))
    entries))

(defun mihomo-proxies-refresh ()
  "Refresh the Mihomo proxy group buffer."
  (interactive)
  (let ((buffer (current-buffer)))
    (mihomo-api-proxies
     (lambda (response error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (setq mihomo-proxies--data (gethash "proxies" response)
                   tabulated-list-entries (mihomo-proxies--entries response))
             (tabulated-list-print t))))))))

(defun mihomo-proxies--selected-group ()
  "Return the selected proxy group name."
  (or (tabulated-list-get-id)
      (user-error "No Mihomo proxy group on this line")))

(defun mihomo-proxies-select ()
  "Select a proxy in the group at point."
  (interactive)
  (let* ((buffer (current-buffer))
         (group (mihomo-proxies--selected-group))
         (proxy (and (hash-table-p mihomo-proxies--data)
                     (gethash group mihomo-proxies--data)))
         (candidates (and proxy (gethash "all" proxy))))
    (unless (consp candidates)
      (user-error "%s is not a selectable Mihomo proxy group" group))
    (let ((selection (completing-read
                      (format "Proxy for %s: " group) candidates nil t
                      nil nil (gethash "now" proxy))))
      (mihomo-api-select-proxy
       group selection
       (lambda (_result error)
         (if error
             (message "Mihomo: %s" (mihomo-api--error-message error))
           (message "Mihomo: %s now uses %s" group selection)
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (mihomo-proxies-refresh)))))))))

(defun mihomo-proxies-test-delay (&optional all)
  "Test delay for the group at point.
With prefix argument ALL, prompt for any proxy or group."
  (interactive "P")
  (let* ((names (and (hash-table-p mihomo-proxies--data)
                     (hash-table-keys mihomo-proxies--data)))
         (proxy (if all
                    (completing-read "Proxy or group: " names nil t)
                  (mihomo-proxies--selected-group))))
    (mihomo-api-proxy-delay
     proxy
     (lambda (result error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (message "Mihomo: %s delay is %s ms"
                  proxy (or (gethash "delay" result) "unknown")))))))

(defvar-keymap mihomo-proxies-mode-map
  :doc "Keymap for `mihomo-proxies-mode'."
  :parent tabulated-list-mode-map
  "RET" #'mihomo-proxies-select
  "s" #'mihomo-proxies-select
  "d" #'mihomo-proxies-test-delay
  "D" (lambda () (interactive) (mihomo-proxies-test-delay t))
  "g" #'mihomo-proxies-refresh)

(define-derived-mode mihomo-proxies-mode tabulated-list-mode "Mihomo-Proxies"
  "Major mode for Mihomo proxy groups."
  (setq tabulated-list-format
        [("Group" 28 t)
         ("Type" 16 t)
         ("Current" 28 t)
         ("Candidates" 10 t)]
        tabulated-list-padding 2
        tabulated-list-sort-key '("Group" . nil))
  (tabulated-list-init-header))

;;;###autoload
(defun mihomo-proxies ()
  "Display Mihomo proxy groups."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Proxies*")))
    (with-current-buffer buffer
      (mihomo-proxies-mode)
      (mihomo-proxies-refresh))
    (pop-to-buffer buffer)))

(provide 'mihomo-proxies)
;;; mihomo-proxies.el ends here
