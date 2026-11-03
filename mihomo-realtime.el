;;; mihomo-realtime.el --- Mihomo realtime logs and traffic -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1") (websocket "1.12"))
;; Version: 0.3.0

;;; Commentary:
;; Realtime Mihomo log and traffic buffers backed by WebSockets.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'mihomo-api)
(require 'subr-x)
(require 'url-util)
(require 'websocket)

(defcustom mihomo-log-level "info"
  "Minimum level requested by the Mihomo log stream."
  :type '(choice (const "debug") (const "info") (const "warning")
                 (const "error") (const "silent"))
  :group 'mihomo)

(defcustom mihomo-log-max-lines 5000
  "Maximum number of lines retained in the Mihomo log buffer."
  :type 'integer
  :group 'mihomo)

(defvar-local mihomo-realtime--socket nil)
(defvar-local mihomo-logs--paused nil)
(defvar-local mihomo-logs--line-count 0)
(defvar-local mihomo-traffic--latest nil)

(defun mihomo-realtime--url (path)
  "Return a WebSocket controller URL for PATH."
  (concat (replace-regexp-in-string
           (rx string-start "http") "ws"
           (string-remove-suffix "/" mihomo-controller-url))
          "/" (string-remove-prefix "/" path)))

(defun mihomo-realtime--headers ()
  "Return authorization headers for a controller WebSocket."
  (when-let* ((secret (mihomo-api--secret)))
    `(("Authorization" . ,(concat "Bearer " secret)))))

(defun mihomo-realtime-disconnect ()
  "Close the WebSocket owned by the current buffer."
  (when mihomo-realtime--socket
    (let ((socket mihomo-realtime--socket))
      (setq mihomo-realtime--socket nil)
      (condition-case nil
          (websocket-close socket)
        (error nil)))))

(defun mihomo-realtime--connect (path message-handler header-handler)
  "Connect current buffer to PATH and use MESSAGE-HANDLER.
Call HEADER-HANDLER with connection status strings."
  (mihomo-realtime-disconnect)
  (let ((buffer (current-buffer)))
    (condition-case error
        (setq mihomo-realtime--socket
              (websocket-open
               (mihomo-realtime--url path)
               :custom-header-alist (mihomo-realtime--headers)
               :nowait t
               :on-open
               (lambda (_socket)
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (funcall header-handler "connected"))))
               :on-message
               (lambda (_socket frame)
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (funcall message-handler
                              (websocket-frame-payload frame)))))
               :on-close
               (lambda (socket)
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (when (eq socket mihomo-realtime--socket)
                       (setq mihomo-realtime--socket nil)
                       (funcall header-handler "disconnected")))))
               :on-error
               (lambda (_socket _where callback-error)
                 (when (buffer-live-p buffer)
                   (with-current-buffer buffer
                     (funcall header-handler "error")
                     (message "Mihomo WebSocket: %s"
                              (error-message-string callback-error)))))))
      (error
       (funcall header-handler "error")
       (message "Mihomo WebSocket: %s" (error-message-string error))))))

(defun mihomo-logs--set-header (status)
  "Set log buffer header to STATUS."
  (setq header-line-format
        (format " Mihomo Logs  level: %s  status: %s%s"
                mihomo-log-level status
                (if mihomo-logs--paused "  PAUSED" ""))))

(defun mihomo-logs--face (level)
  "Return a face for log LEVEL."
  (pcase level
    ((or "error" "fatal" "panic") 'error)
    ((or "warn" "warning") 'warning)
    ("debug" 'font-lock-comment-face)
    (_ 'default)))

(defun mihomo-logs--on-message (payload)
  "Insert structured log PAYLOAD into the current buffer."
  (unless mihomo-logs--paused
    (condition-case error
        (let* ((entry (json-parse-string payload :object-type 'hash-table))
               (time (or (gethash "time" entry) "--:--:--"))
               (level (or (gethash "level" entry) "info"))
               (message-text (or (gethash "message" entry) ""))
               (inhibit-read-only t))
          (goto-char (point-max))
          (insert (format "[%s] %-5s %s\n"
                          time
                          (propertize (upcase level) 'face
                                      (mihomo-logs--face level))
                          message-text))
          (cl-incf mihomo-logs--line-count)
          (when (> mihomo-logs--line-count mihomo-log-max-lines)
            (goto-char (point-min))
            (delete-region (point) (progn (forward-line 1) (point)))
            (cl-decf mihomo-logs--line-count))
          (goto-char (point-max)))
      (error
       (message "Mihomo log payload: %s" (error-message-string error))))))

(defun mihomo-logs-connect ()
  "Connect or reconnect the current Mihomo log buffer."
  (interactive)
  (mihomo-realtime--connect
   (concat "/logs?"
           (url-build-query-string
            `(("level" ,mihomo-log-level) ("format" "structured"))))
   #'mihomo-logs--on-message #'mihomo-logs--set-header))

(defun mihomo-logs-toggle-pause ()
  "Toggle insertion of Mihomo log messages."
  (interactive)
  (setq mihomo-logs--paused (not mihomo-logs--paused))
  (mihomo-logs--set-header
   (if (and mihomo-realtime--socket
            (websocket-openp mihomo-realtime--socket))
       "connected" "disconnected")))

(defun mihomo-logs-clear ()
  "Clear the current Mihomo log buffer."
  (interactive)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (setq mihomo-logs--line-count 0)))

(defun mihomo-logs-set-level (level)
  "Set Mihomo log LEVEL and reconnect."
  (interactive
   (list (completing-read "Mihomo log level: "
                          '("debug" "info" "warning" "error" "silent")
                          nil t nil nil mihomo-log-level)))
  (setq mihomo-log-level level)
  (mihomo-logs-connect))

(defvar-keymap mihomo-logs-mode-map
  :doc "Keymap for `mihomo-logs-mode'."
  :parent special-mode-map
  "g" #'mihomo-logs-connect
  "p" #'mihomo-logs-toggle-pause
  "c" #'mihomo-logs-clear
  "l" #'mihomo-logs-set-level)

(define-derived-mode mihomo-logs-mode special-mode "Mihomo-Logs"
  "Major mode for realtime Mihomo logs."
  (setq-local mihomo-logs--line-count 0
              mihomo-logs--paused nil)
  (add-hook 'kill-buffer-hook #'mihomo-realtime-disconnect nil t)
  (mihomo-logs--set-header "disconnected"))

;;;###autoload
(defun mihomo-logs ()
  "Display realtime Mihomo logs."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Logs*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'mihomo-logs-mode)
        (mihomo-logs-mode))
      (mihomo-logs-connect))
    (pop-to-buffer buffer)))

(defun mihomo-traffic--set-header (status)
  "Set traffic buffer header to STATUS."
  (setq header-line-format (format " Mihomo Traffic  status: %s" status)))

(defun mihomo-traffic--render (payload)
  "Render traffic JSON PAYLOAD in the current buffer."
  (condition-case error
      (let* ((traffic (json-parse-string payload :object-type 'hash-table))
             (inhibit-read-only t))
        (setq mihomo-traffic--latest traffic)
        (erase-buffer)
        (insert "Mihomo Traffic\n\n"
                (format "Upload     %s/s\n"
                        (file-size-human-readable (gethash "up" traffic 0)))
                (format "Download   %s/s\n\n"
                        (file-size-human-readable (gethash "down" traffic 0)))
                (format "Uploaded   %s\n"
                        (file-size-human-readable
                         (gethash "upTotal" traffic 0)))
                (format "Downloaded %s\n\n"
                        (file-size-human-readable
                         (gethash "downTotal" traffic 0)))
                (format "Updated    %s\n" (format-time-string "%T"))))
    (error
     (message "Mihomo traffic payload: %s" (error-message-string error)))))

(defun mihomo-traffic-connect ()
  "Connect or reconnect the current Mihomo traffic buffer."
  (interactive)
  (mihomo-realtime--connect
   "/traffic" #'mihomo-traffic--render #'mihomo-traffic--set-header))

(defvar-keymap mihomo-traffic-mode-map
  :doc "Keymap for `mihomo-traffic-mode'."
  :parent special-mode-map
  "g" #'mihomo-traffic-connect)

(define-derived-mode mihomo-traffic-mode special-mode "Mihomo-Traffic"
  "Major mode for realtime Mihomo traffic."
  (add-hook 'kill-buffer-hook #'mihomo-realtime-disconnect nil t)
  (mihomo-traffic--set-header "disconnected"))

;;;###autoload
(defun mihomo-traffic ()
  "Display realtime Mihomo traffic."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Traffic*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'mihomo-traffic-mode)
        (mihomo-traffic-mode))
      (mihomo-traffic-connect))
    (pop-to-buffer buffer)))

(provide 'mihomo-realtime)
;;; mihomo-realtime.el ends here
