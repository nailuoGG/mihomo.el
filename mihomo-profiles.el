;;; mihomo-profiles.el --- Mihomo configuration profiles -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.5.0

;;; Commentary:
;; Safely update and activate local or subscribed Mihomo configurations.

;;; Code:

(require 'mihomo-api)
(require 'mihomo-config-mode)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-http)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

(defcustom mihomo-profiles nil
  "Mihomo configuration profiles.
Each entry is a plist with `:name', `:file', and optional `:url'."
  :type '(repeat
          (list :tag "Profile"
                (const :format "" :name)
                (string :tag "Name")
                (const :format "" :file)
                (file :tag "Configuration file")
                (const :format "" :url)
                (choice :tag "Subscription"
                        (const :tag "Local only" nil)
                        (string :tag "URL"))))
  :group 'mihomo)

(defcustom mihomo-profile-max-download-size (* 10 1024 1024)
  "Maximum accepted subscription response size in bytes."
  :type 'integer
  :group 'mihomo)

(defvar mihomo-profile-current nil
  "Name of the last profile activated through mihomo.el.")

(defun mihomo-profile--validate (profile)
  "Validate and normalize PROFILE."
  (let ((name (plist-get profile :name))
        (file (plist-get profile :file))
        (url (plist-get profile :url)))
    (unless (and (stringp name) (not (string-empty-p name)))
      (user-error "Mihomo profile requires a nonempty :name"))
    (unless (and (stringp file) (not (string-empty-p file)))
      (user-error "Mihomo profile %s requires a :file" name))
    (when (and url
               (not (and (stringp url)
                         (string-match-p (rx string-start "http"
                                             (optional "s") "://")
                                         url))))
      (user-error "Mihomo profile %s requires an HTTP(S) :url" name))
    (list :name name :file (expand-file-name file) :url url)))

(defun mihomo-profile-list ()
  "Return validated profiles and reject duplicate names."
  (let ((names (make-hash-table :test #'equal)))
    (mapcar
     (lambda (profile)
       (let* ((validated (mihomo-profile--validate profile))
              (name (plist-get validated :name)))
         (when (gethash name names)
           (user-error "Duplicate Mihomo profile name: %s" name))
         (puthash name t names)
         validated))
     mihomo-profiles)))

(defun mihomo-profile-find (name)
  "Return profile NAME or signal a user error."
  (or (seq-find (lambda (profile)
                  (equal (plist-get profile :name) name))
                (mihomo-profile-list))
      (user-error "Unknown Mihomo profile: %s" name)))

(defun mihomo-profile-validate-file (file callback)
  "Validate Mihomo configuration FILE, then call CALLBACK.
CALLBACK receives SUCCESS and MESSAGE."
  (cond
   ((not (file-readable-p file))
    (funcall callback nil (format "Configuration is not readable: %s" file)))
   ((not (executable-find mihomo-executable))
    (funcall callback nil
             (format "Cannot find Mihomo executable: %s" mihomo-executable)))
   (t
    (let ((output-buffer (generate-new-buffer " *mihomo-profile-check*")))
      (make-process
       :name "mihomo-profile-check"
       :buffer output-buffer
       :command (list mihomo-executable "-t" "-f" file)
       :connection-type 'pipe
       :noquery t
       :sentinel
       (lambda (process _event)
         (when (memq (process-status process) '(exit signal))
           (let ((success (and (eq (process-status process) 'exit)
                               (zerop (process-exit-status process))))
                 (message-text
                  (with-current-buffer output-buffer
                    (string-trim (buffer-string)))))
             (kill-buffer output-buffer)
             (funcall callback success
                      (if (string-empty-p message-text)
                          (if success "Configuration is valid"
                            "Mihomo rejected the configuration")
                        message-text))))))))))

(defun mihomo-profile--finish-download (profile temp-file callback)
  "Validate TEMP-FILE and replace PROFILE file before calling CALLBACK."
  (mihomo-profile-validate-file
   temp-file
   (lambda (success message-text)
     (if (not success)
         (progn
           (when (file-exists-p temp-file)
             (delete-file temp-file))
           (funcall callback nil message-text))
       (condition-case error
           (progn
             (rename-file temp-file (plist-get profile :file) t)
             (funcall callback t "Subscription updated"))
         (error
          (when (file-exists-p temp-file)
            (delete-file temp-file))
          (funcall callback nil (error-message-string error))))))))

(defun mihomo-profile--download-response (status profile temp-file callback)
  "Handle subscription STATUS for PROFILE into TEMP-FILE and CALLBACK."
  (let ((response-buffer (current-buffer)) failure)
    (unwind-protect
        (condition-case error
            (let ((network-error (plist-get status :error))
                  (code url-http-response-status))
              (cond
               ((and network-error (not code))
                (setq failure "Subscription download failed"))
               ((not (and code (<= 200 code) (< code 300)))
                (setq failure
                      (format "Subscription server returned HTTP %s"
                              (or code "unknown"))))
               (t
                (goto-char url-http-end-of-headers)
                (skip-chars-forward "\r\n")
                (let ((size (- (point-max) (point))))
                  (if (> size mihomo-profile-max-download-size)
                      (setq failure
                            (format "Subscription exceeds %d bytes"
                                    mihomo-profile-max-download-size))
                    (let ((coding-system-for-write 'utf-8-unix))
                      (write-region (point) (point-max) temp-file nil 'silent)))))))
          (error (setq failure (error-message-string error))))
      (when (buffer-live-p response-buffer)
        (kill-buffer response-buffer)))
    (if failure
        (progn
          (when (file-exists-p temp-file)
            (delete-file temp-file))
          (funcall callback nil failure))
      (mihomo-profile--finish-download profile temp-file callback))))

(defun mihomo-profile-update (profile callback)
  "Download and validate subscribed PROFILE, then call CALLBACK.
CALLBACK receives SUCCESS and MESSAGE."
  (let* ((validated (mihomo-profile--validate profile))
         (url (plist-get validated :url))
         (file (plist-get validated :file)))
    (unless url
      (user-error "Mihomo profile %s has no subscription URL"
                  (plist-get validated :name)))
    (let ((directory (file-name-directory file)))
      (make-directory directory t)
      (let ((temp-file
             (make-temp-file
              (expand-file-name ".mihomo-subscription-" directory)
              nil ".yaml")))
        (condition-case nil
            (url-retrieve
             url #'mihomo-profile--download-response
             (list validated temp-file callback) t t)
          (error
           (when (file-exists-p temp-file)
             (delete-file temp-file))
           (funcall callback nil "Subscription download could not start")))))))

(defun mihomo-profile-activate (profile callback)
  "Validate and activate PROFILE, then call CALLBACK.
CALLBACK receives SUCCESS and MESSAGE."
  (let* ((validated (mihomo-profile--validate profile))
         (name (plist-get validated :name))
         (file (plist-get validated :file)))
    (mihomo-profile-validate-file
     file
     (lambda (success message-text)
       (if (not success)
           (funcall callback nil message-text)
         (mihomo-api-reload-config
          file
          (lambda (_result error)
            (if error
                (funcall callback nil (mihomo-api--error-message error))
              (setq mihomo-profile-current name)
              (funcall callback t (format "Activated profile %s" name))))))))))

(defun mihomo-profile--entries ()
  "Return tabulated profile entries."
  (mapcar
   (lambda (profile)
     (let* ((name (plist-get profile :name))
            (file (plist-get profile :file))
            (url (plist-get profile :url)))
       (list name
             (vector name
                     (if url "Subscription" "Local")
                     (abbreviate-file-name file)
                     (if (file-exists-p file) "present" "missing")
                     (if (equal name mihomo-profile-current) "*" "")))))
   (mihomo-profile-list)))

(defun mihomo-profiles-ui-refresh ()
  "Refresh the Mihomo profile buffer."
  (interactive)
  (setq tabulated-list-entries (mihomo-profile--entries))
  (tabulated-list-print t))

(defun mihomo-profiles-ui--selected ()
  "Return the profile name at point."
  (or (tabulated-list-get-id)
      (user-error "No Mihomo profile on this line")))

(defun mihomo-profiles-ui-update ()
  "Update the subscription for the profile at point."
  (interactive)
  (let* ((name (mihomo-profiles-ui--selected))
         (profile (mihomo-profile-find name))
         (buffer (current-buffer)))
    (mihomo-profile-update
     profile
     (lambda (success message-text)
       (message "Mihomo profile %s: %s" name
                (if success message-text (concat "failed - " message-text)))
       (when (and (buffer-live-p buffer) success)
         (with-current-buffer buffer
           (mihomo-profiles-ui-refresh)))))))

(defun mihomo-profiles-ui-activate ()
  "Activate the profile at point on the running controller."
  (interactive)
  (let* ((name (mihomo-profiles-ui--selected))
         (profile (mihomo-profile-find name)))
    (mihomo-profile-activate
     profile
     (lambda (success message-text)
       (message "Mihomo profile %s: %s" name
                (if success message-text (concat "failed - " message-text)))))))

(defun mihomo-profiles-ui-open ()
  "Open the configuration file of the profile at point."
  (interactive)
  (let* ((profile (mihomo-profile-find (mihomo-profiles-ui--selected)))
         (file (plist-get profile :file)))
    (unless (file-exists-p file)
      (user-error "Mihomo profile file is missing: %s" file))
    (find-file file)))

(defvar-keymap mihomo-profiles-ui-mode-map
  :doc "Keymap for `mihomo-profiles-ui-mode'."
  :parent tabulated-list-mode-map
  "u" #'mihomo-profiles-ui-update
  "a" #'mihomo-profiles-ui-activate
  "o" #'mihomo-profiles-ui-open
  "g" #'mihomo-profiles-ui-refresh)

(define-derived-mode mihomo-profiles-ui-mode tabulated-list-mode
  "Mihomo-Profiles"
  "Major mode for Mihomo configuration profiles."
  (setq tabulated-list-format
        [("Name" 22 t)
         ("Kind" 12 t)
         ("File" 45 t)
         ("Status" 9 t)
         ("Active" 7 t)]
        tabulated-list-padding 2
        tabulated-list-sort-key '("Name" . nil))
  (tabulated-list-init-header))

;;;###autoload
(defun mihomo-profiles-ui ()
  "Display Mihomo configuration profiles."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Profiles*")))
    (with-current-buffer buffer
      (mihomo-profiles-ui-mode)
      (mihomo-profiles-ui-refresh))
    (pop-to-buffer buffer)))

(provide 'mihomo-profiles)
;;; mihomo-profiles.el ends here
