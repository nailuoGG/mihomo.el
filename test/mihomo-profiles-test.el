;;; mihomo-profiles-test.el --- Tests for Mihomo profiles -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-profiles)

(ert-deftest mihomo-profile-validates-and-expands-files ()
  (let ((profile (mihomo-profile--validate
                  (list :name "Local" :file "~/config.yaml" :url nil))))
    (should (equal (plist-get profile :name) "Local"))
    (should (string-prefix-p "/" (plist-get profile :file)))))

(ert-deftest mihomo-profile-rejects-invalid-definitions ()
  (should-error (mihomo-profile--validate (list :name "" :file "/tmp/x"))
                :type 'user-error)
  (should-error (mihomo-profile--validate (list :name "A"))
                :type 'user-error)
  (should-error (mihomo-profile--validate
                 (list :name "A" :file "/tmp/x" :url "ftp://example.com"))
                :type 'user-error))

(ert-deftest mihomo-profile-rejects-duplicate-names ()
  (let ((mihomo-profiles
         (list (list :name "Same" :file "/tmp/a.yaml")
               (list :name "Same" :file "/tmp/b.yaml"))))
    (should-error (mihomo-profile-list) :type 'user-error)))

(ert-deftest mihomo-profile-finds-declared-profile ()
  (let ((mihomo-profiles
         (list (list :name "Local" :file "/tmp/config.yaml"))))
    (should (equal (plist-get (mihomo-profile-find "Local") :file)
                   "/tmp/config.yaml"))
    (should-error (mihomo-profile-find "Missing") :type 'user-error)))

(ert-deftest mihomo-profile-update-requires-url ()
  (should-error (mihomo-profile-update
                 (list :name "Local" :file "/tmp/config.yaml") #'ignore)
                :type 'user-error))

(ert-deftest mihomo-profile-download-rejects-http-error ()
  (let ((profile (mihomo-profile--validate
                  (list :name "Sub" :file "/tmp/mihomo-test/profile.yaml"
                        :url "https://example.com/sub")))
        (temp-file (make-temp-file "mihomo-profile-test-" nil ".yaml"))
        result failure)
    (with-temp-buffer
      (insert "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nmissing")
      (setq-local url-http-response-status 404
                  url-http-end-of-headers
                  (copy-marker (save-excursion
                                 (goto-char (point-min))
                                 (search-forward "\r\n\r\n"))))
      (mihomo-profile--download-response nil profile temp-file
                                         (lambda (success message)
                                           (setq result success
                                                 failure message))))
    (should-not result)
    (should (string-match-p "HTTP 404" failure))
    (should-not (file-exists-p temp-file))))

(ert-deftest mihomo-profile-download-rejects-oversized-response ()
  (let* ((profile (mihomo-profile--validate
                   (list :name "Sub" :file "/tmp/mihomo-test/profile.yaml"
                         :url "https://example.com/sub")))
         (temp-file (make-temp-file "mihomo-profile-test-" nil ".yaml"))
         (mihomo-profile-max-download-size 8)
         result failure)
    (with-temp-buffer
      (insert "HTTP/1.1 200 OK\r\nContent-Type: text/yaml\r\n\r\n"
              "mode: rule\nproxies: []\nrules: []\n")
      (setq-local url-http-response-status 200
                  url-http-end-of-headers
                  (copy-marker (save-excursion
                                 (goto-char (point-min))
                                 (search-forward "\r\n\r\n"))))
      (mihomo-profile--download-response nil profile temp-file
                                         (lambda (success message)
                                           (setq result success
                                                 failure message))))
    (should-not result)
    (should (string-match-p "exceeds" failure))
    (should-not (file-exists-p temp-file))))

(provide 'mihomo-profiles-test)
;;; mihomo-profiles-test.el ends here
