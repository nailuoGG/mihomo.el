;;; mihomo-flymake.el --- Flymake backend for Mihomo -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.4.0

;;; Commentary:
;; Validate a Mihomo configuration with `mihomo -t'.

;;; Code:

(require 'cl-lib)
(require 'flymake)
(require 'subr-x)

(defvar-local mihomo-flymake--process nil)

(defun mihomo-flymake--diagnostics (source output)
  "Create Flymake diagnostics for SOURCE from Mihomo OUTPUT."
  (with-current-buffer source
    (let ((case-fold-search t)
          diagnostics)
      (dolist (line (split-string output "\n" t))
        (when (string-match
               (rx "line " (group (+ digit))
                   (optional (or ":" (seq (+ blank) "column"))
                             (* blank) (group (+ digit))))
               line)
          (let* ((line-number (string-to-number (match-string 1 line)))
                 (column (and (match-string 2 line)
                              (string-to-number (match-string 2 line))))
                 (region (flymake-diag-region source line-number column)))
            (push (flymake-make-diagnostic
                   source (car region) (cdr region) :error (string-trim line))
                  diagnostics))))
      (unless (or diagnostics (string-empty-p (string-trim output)))
        (push (flymake-make-diagnostic
               source (point-min) (min (1+ (point-min)) (point-max))
               :error (string-trim output))
              diagnostics))
      (nreverse diagnostics))))

(defun mihomo-flymake-backend (report-fn &rest _args)
  "Validate the current buffer with Mihomo and call REPORT-FN."
  (if (not (executable-find mihomo-executable))
      (funcall report-fn nil
               :explanation
               (format "Cannot find Mihomo executable: %s" mihomo-executable))
    (when (process-live-p mihomo-flymake--process)
      (kill-process mihomo-flymake--process))
    (let* ((source (current-buffer))
           (directory (or (and buffer-file-name
                               (file-name-directory buffer-file-name))
                          temporary-file-directory))
           (temp-file (make-temp-file
                       (expand-file-name ".mihomo-flymake-" directory)
                       nil ".yaml"))
           (output-buffer (generate-new-buffer " *mihomo-flymake*")))
      (write-region nil nil temp-file nil 'silent)
      (setq mihomo-flymake--process
            (make-process
             :name "mihomo-flymake"
             :buffer output-buffer
             :command (list mihomo-executable "-t" "-f" temp-file)
             :connection-type 'pipe
             :noquery t
             :sentinel
             (lambda (process _event)
               (when (memq (process-status process) '(exit signal))
                 (unwind-protect
                     (when (and (buffer-live-p source)
                                (with-current-buffer source
                                  (eq process mihomo-flymake--process)))
                       (with-current-buffer output-buffer
                         (funcall report-fn
                                  (mihomo-flymake--diagnostics
                                   source (buffer-string)))))
                   (when (file-exists-p temp-file)
                     (delete-file temp-file))
                   (when (buffer-live-p output-buffer)
                     (kill-buffer output-buffer))))))))))

(provide 'mihomo-flymake)
;;; mihomo-flymake.el ends here
