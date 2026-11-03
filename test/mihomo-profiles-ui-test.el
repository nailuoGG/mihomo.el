;;; mihomo-profiles-ui-test.el --- Tests for the Mihomo profile UI -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-profiles)

(ert-deftest mihomo-profiles-ui-builds-entries ()
  (let ((mihomo-profiles
         (list (list :name "Local" :file "/tmp/mihomo-present.yaml")
               (list :name "Sub" :file "/tmp/mihomo-missing.yaml"
                     :url "https://example.com/sub")))
        (mihomo-profile-current "Local")
        entries)
    (cl-letf (((symbol-function 'file-exists-p)
               (lambda (file)
                 (equal file "/tmp/mihomo-present.yaml"))))
      (setq entries (mihomo-profile--entries)))
    (should (= (length entries) 2))
    (should (equal (caar entries) "Local"))
    (should (equal (append (cadar entries) nil)
                   '("Local" "Local" "/tmp/mihomo-present.yaml" "present" "*")))
    (should (equal (append (cadr (cadr entries)) nil)
                   '("Sub" "Subscription" "/tmp/mihomo-missing.yaml"
                     "missing" "")))))

(ert-deftest mihomo-profiles-ui-renders-into-tabulated-buffer ()
  (let ((mihomo-profiles
         (list (list :name "Local" :file "/tmp/mihomo-present.yaml")))
        (mihomo-profile-current nil)
        (buffer (generate-new-buffer " *mihomo-profiles-ui-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (mihomo-profiles-ui-mode)
          (mihomo-profiles-ui-refresh)
          (should (equal major-mode 'mihomo-profiles-ui-mode))
          (should (= (length tabulated-list-entries) 1))
          (should (string-match-p "Local" (buffer-string))))
      (kill-buffer buffer))))

(provide 'mihomo-profiles-ui-test)
;;; mihomo-profiles-ui-test.el ends here
