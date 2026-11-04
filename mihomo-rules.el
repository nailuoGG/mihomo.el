;;; mihomo-rules.el --- Browse active Mihomo rules -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.4.0

;;; Commentary:
;; Paginated and filterable active rule browser for Mihomo.

;;; Code:

(require 'cl-lib)
(require 'mihomo-api)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)

(defcustom mihomo-rules-page-size 200
  "Number of rules shown on one page."
  :type 'integer
  :group 'mihomo)

(defvar-local mihomo-rules--all nil)
(defvar-local mihomo-rules--filter "")
(defvar-local mihomo-rules--page 0)

(defun mihomo-rules--matches-p (rule)
  "Return non-nil when RULE matches the current filter."
  (or (string-empty-p mihomo-rules--filter)
      (let ((needle (downcase mihomo-rules--filter)))
        (seq-some
         (lambda (value)
           (and (stringp value)
                (string-match-p (regexp-quote needle) (downcase value))))
         (list (gethash "type" rule)
               (gethash "payload" rule)
               (gethash "proxy" rule))))))

(defun mihomo-rules--filtered ()
  "Return rules matching the current filter."
  (seq-filter #'mihomo-rules--matches-p mihomo-rules--all))

(defun mihomo-rules--entry (rule)
  "Return one tabulated entry for RULE."
  (let ((extra (gethash "extra" rule)))
    (list (gethash "index" rule)
          (vector
           (number-to-string (gethash "index" rule 0))
           (or (gethash "type" rule) "")
           (or (gethash "payload" rule) "")
           (or (gethash "proxy" rule) "")
           (number-to-string (or (and extra (gethash "hitCount" extra)) 0))
           (if (and extra (eq (gethash "disabled" extra) t)) "yes" "")))))

(defun mihomo-rules--render ()
  "Render the current rule page."
  (let* ((rules (mihomo-rules--filtered))
         (count (length rules))
         (pages (max 1 (ceiling count mihomo-rules-page-size))))
    (setq mihomo-rules--page (min mihomo-rules--page (1- pages)))
    (let* ((start (* mihomo-rules--page mihomo-rules-page-size))
           (end (min count (+ start mihomo-rules-page-size))))
      (setq tabulated-list-entries
            (mapcar #'mihomo-rules--entry (seq-subseq rules start end))
            header-line-format
            (format " Mihomo Rules  page %d/%d  showing %d-%d of %d%s"
                    (1+ mihomo-rules--page) pages
                    (if (zerop count) 0 (1+ start)) end count
                    (if (string-empty-p mihomo-rules--filter)
                        "" (format "  filter: %s" mihomo-rules--filter))))
      (tabulated-list-print t))))

(defun mihomo-rules-refresh ()
  "Refresh active Mihomo rules."
  (interactive)
  (let ((buffer (current-buffer)))
    (mihomo-api-rules
     (lambda (response error)
       (if error
           (message "Mihomo: %s" (mihomo-api--error-message error))
         (when (buffer-live-p buffer)
           (with-current-buffer buffer
             (setq mihomo-rules--all (gethash "rules" response)
                   mihomo-rules--page 0)
             (mihomo-rules--render))))))))

(defun mihomo-rules-next-page ()
  "Display the next rule page."
  (interactive)
  (let* ((count (length (mihomo-rules--filtered)))
         (pages (max 1 (ceiling count mihomo-rules-page-size))))
    (if (< (1+ mihomo-rules--page) pages)
        (progn (cl-incf mihomo-rules--page) (mihomo-rules--render))
      (user-error "Already on the last Mihomo rule page"))))

(defun mihomo-rules-previous-page ()
  "Display the previous rule page."
  (interactive)
  (if (> mihomo-rules--page 0)
      (progn (cl-decf mihomo-rules--page) (mihomo-rules--render))
    (user-error "Already on the first Mihomo rule page")))

(defun mihomo-rules-filter (filter)
  "Filter rules by text FILTER."
  (interactive (list (read-string "Rule filter: " mihomo-rules--filter)))
  (setq mihomo-rules--filter filter
        mihomo-rules--page 0)
  (mihomo-rules--render))

(defun mihomo-rules-clear-filter ()
  "Clear the current rule filter."
  (interactive)
  (setq mihomo-rules--filter ""
        mihomo-rules--page 0)
  (mihomo-rules--render))

(defvar-keymap mihomo-rules-mode-map
  :doc "Keymap for `mihomo-rules-mode'."
  :parent tabulated-list-mode-map
  "n" #'mihomo-rules-next-page
  "p" #'mihomo-rules-previous-page
  "f" #'mihomo-rules-filter
  "c" #'mihomo-rules-clear-filter
  "g" #'mihomo-rules-refresh)

(define-derived-mode mihomo-rules-mode tabulated-list-mode "Mihomo-Rules"
  "Major mode for active Mihomo rules."
  (setq tabulated-list-format
        [("Index" 7 t)
         ("Type" 18 t)
         ("Payload" 45 t)
         ("Target" 22 t)
         ("Hits" 10 t)
         ("Disabled" 9 t)]
        tabulated-list-padding 2
        tabulated-list-sort-key nil
        tabulated-list-use-header-line nil)
  (tabulated-list-init-header))

;;;###autoload
(defun mihomo-rules ()
  "Display active Mihomo rules."
  (interactive)
  (let ((buffer (get-buffer-create "*Mihomo Rules*")))
    (with-current-buffer buffer
      (mihomo-rules-mode)
      (mihomo-rules-refresh))
    (pop-to-buffer buffer)))

(provide 'mihomo-rules)
;;; mihomo-rules.el ends here
