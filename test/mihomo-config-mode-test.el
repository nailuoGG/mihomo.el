;;; mihomo-config-mode-test.el --- Tests for mihomo-config-mode -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-config-mode)
(require 'mihomo-flymake)

(defmacro mihomo-test-with-config-buffer (content &rest body)
  "Create a Mihomo config buffer containing CONTENT and run BODY."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,content)
     (goto-char (point-min))
     (cl-letf (((symbol-function 'flymake-mode) #'ignore))
       (mihomo-config-mode))
     ,@body))

(ert-deftest mihomo-config-mode-derives-from-yaml-mode ()
  (mihomo-test-with-config-buffer "mode: rule\n"
    (should (derived-mode-p 'yaml-mode))))

(ert-deftest mihomo-config-mode-completes-top-level-key ()
  (mihomo-test-with-config-buffer "proxy-g"
    (goto-char (point-max))
    (pcase-let ((`(,start ,end ,collection . ,_)
                 (mihomo-config-completion-at-point)))
      (should (equal (buffer-substring start end) "proxy-g"))
      (should (member "proxy-groups" collection)))))

(ert-deftest mihomo-config-mode-completes-nested-key ()
  (mihomo-test-with-config-buffer "proxies:\n  serv"
    (goto-char (point-max))
    (pcase-let ((`(,_start ,_end ,collection . ,_)
                 (mihomo-config-completion-at-point)))
      (should (member "server" collection))
      (should-not (member "proxy-groups" collection)))))

(ert-deftest mihomo-config-mode-inserts-indented-snippet ()
  (mihomo-test-with-config-buffer "rules:\n  "
    (goto-char (point-max))
    (mihomo-config-insert-snippet "rule/domain")
    (should (equal (buffer-string)
                   "rules:\n  - DOMAIN,example.com,DIRECT"))))

(ert-deftest mihomo-config-mode-highlights-rule-type ()
  (mihomo-test-with-config-buffer "rules:\n  - DOMAIN,example.com,DIRECT\n"
    (font-lock-ensure)
    (goto-char (point-min))
    (search-forward "DOMAIN")
    (should (eq (get-text-property (1- (point)) 'face)
                'font-lock-builtin-face))))

(ert-deftest mihomo-flymake-parses-line-diagnostic ()
  (with-temp-buffer
    (insert "mode: rule\nrules:\n  - INVALID\n")
    (let ((diagnostics
           (mihomo-flymake--diagnostics
            (current-buffer) "configuration error: yaml: line 3: bad rule")))
      (should (= (length diagnostics) 1))
      (should (= (line-number-at-pos
                  (flymake-diagnostic-beg (car diagnostics)))
                 3))
      (should (string-match-p "bad rule"
                              (flymake-diagnostic-text (car diagnostics)))))))

(ert-deftest mihomo-flymake-reports-unlocated-error-at-buffer-start ()
  (with-temp-buffer
    (insert "mode: rule\n")
    (let ((diagnostic
           (car (mihomo-flymake--diagnostics
                 (current-buffer) "configuration file is invalid"))))
      (should (= (flymake-diagnostic-beg diagnostic) (point-min)))
      (should (equal (flymake-diagnostic-text diagnostic)
                     "configuration file is invalid")))))

(provide 'mihomo-config-mode-test)
;;; mihomo-config-mode-test.el ends here
