;;; mihomo-connections.el --- Mihomo connection interface -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.2.0

;;; Commentary:
;; Tabulated active connection management for the Mihomo controller.

;;; Code:

(require 'mihomo-api)
(require 'subr-x)
(require 'tabulated-list)

(defun mihomo-connections--human-size (value)
  "Format byte VALUE for the connection table."
  (file-size-human-readable (or value 0)))

(defun mihomo-connections--entries (response)
  "Return tabulated entries from connection RESPONSE."
  (mapcar
   (lambda (connection)
     (let* ((metadata (gethash "metadata" connection))
            (host (or (and metadata (gethash "host" metadata))
                      (and metadata (gethash "destinationIP" metadata))
                      ""))
            (chains (gethash "chains" connection)))
       (list (gethash "id" connection)
             (vector host
                     (or (and metadata (gethash "network" metadata)) "")
                     (or (gethash "rule" connection) "")
                     (if (listp chains) (string-join chains " → ") "")
                     (mihomo-connections--human-size
                      (gethash "upload" connection))
                     (mihomo-connections--human-size
                      (gethash "download" connection))))))
   (or (gethash "connections" response) nil)))

(defun mihomo-connections-refresh ()
  "Refresh the Mihomo connections buffer."
  (interactive)
  (let ((buffer (current-buffer)))
    (mihomo-api-connections
     (lambda (response error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (setq tabulated-list-entries
                   (mihomo-connections--entries response))
             (tabulated-list-print t))))))))

(defun mihomo-connections-close ()
  "Close the Mihomo connection at point."
  (interactive)
  (let ((id (or (tabulated-list-get-id)
                (user-error "No Mihomo connection on this line")))
        (buffer (current-buffer)))
    (mihomo-api-close-connection
     id
     (lambda (_result error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (message "Mihomo: connection closed")
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (mihomo-connections-refresh))))))))

(defun mihomo-connections-close-all ()
  "Close all Mihomo connections after confirmation."
  (interactive)
  (when (yes-or-no-p "Close all Mihomo connections? ")
    (let ((buffer (current-buffer)))
      (mihomo-api-close-all-connections
       (lambda (_result error)
         (if error
             (message "Mihomo: %s" (mihomo-api--error-message error))
           (message "Mihomo: all connections closed")
           (when (buffer-live-p buffer)
             (with-current-buffer buffer
               (mihomo-connections-refresh)))))))))

(defvar-keymap mihomo-connections-mode-map
  :doc "Keymap for `mihomo-connections-mode'."
  :parent tabulated-list-mode-map
  "k" #'mihomo-connections-close
  "K" #'mihomo-connections-close-all
  "g" #'mihomo-connections-refresh)

(define-derived-mode mihomo-connections-mode tabulated-list-mode
  "Mihomo-Connections"
  "Major mode for active Mihomo connections."
  (setq tabulated-list-format
        [("Host" 30 t)
         ("Network" 9 t)
         ("Rule" 18 t)
         ("Chains" 30 t)
         ("Upload" 10 t)
         ("Download" 10 t)]
        tabulated-list-padding 2
        tabulated-list-sort-key '("Host" . nil))
  (tabulated-list-init-header))

;;;###autoload
(defun mihomo-connections ()
  "Display active Mihomo connections."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Connections*")))
    (with-current-buffer buffer
      (mihomo-connections-mode)
      (mihomo-connections-refresh))
    (pop-to-buffer buffer)))

(provide 'mihomo-connections)
;;; mihomo-connections.el ends here
