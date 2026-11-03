;;; mihomo-rules-test.el --- Tests for Mihomo rules -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-rules)

(defun mihomo-rules-test--json (string)
  "Parse rules JSON STRING."
  (json-parse-string string :object-type 'hash-table :array-type 'list))

(ert-deftest mihomo-rules-builds-entry-with-extra-data ()
  (let* ((rule (mihomo-rules-test--json
                "{\"index\":7,\"type\":\"DomainSuffix\",\"payload\":\"example.com\",\"proxy\":\"Proxy\",\"size\":-1,\"extra\":{\"hitCount\":3,\"disabled\":true}}"))
         (entry (mihomo-rules--entry rule)))
    (should (= (car entry) 7))
    (should (equal (append (cadr entry) nil)
                   '("7" "DomainSuffix" "example.com" "Proxy" "3" "yes")))))

(ert-deftest mihomo-rules-paginates-and-filters ()
  (with-temp-buffer
    (mihomo-rules-mode)
    (let ((mihomo-rules-page-size 2))
      (setq mihomo-rules--all
            (gethash
             "rules"
             (mihomo-rules-test--json
              "{\"rules\":[{\"index\":0,\"type\":\"Domain\",\"payload\":\"a.example\",\"proxy\":\"DIRECT\"},{\"index\":1,\"type\":\"Domain\",\"payload\":\"b.example\",\"proxy\":\"Proxy\"},{\"index\":2,\"type\":\"Match\",\"payload\":\"\",\"proxy\":\"DIRECT\"}]}")))
      (mihomo-rules--render)
      (should (= (length tabulated-list-entries) 2))
      (should (string-match-p "page 1/2" header-line-format))
      (should (string-match-p "Index" (buffer-string)))
      (mihomo-rules-next-page)
      (should (= (length tabulated-list-entries) 1))
      (mihomo-rules-filter "DIRECT")
      (should (= (length tabulated-list-entries) 2))
      (should (= mihomo-rules--page 0)))))

(ert-deftest mihomo-api-builds-rule-and-provider-detail-routes ()
  (let (requests)
    (cl-letf (((symbol-function 'mihomo-api--secret) #'ignore)
              ((symbol-function 'url-retrieve)
               (lambda (url _callback _cbargs &rest _args)
                 (push (cons url url-request-method) requests))))
      (let ((mihomo-controller-url "http://127.0.0.1:9090"))
        (mihomo-api-rules #'ignore)
        (mihomo-api-proxy-provider "Provider A" #'ignore)))
    (should (member '("http://127.0.0.1:9090/rules" . "GET") requests))
    (should (member '("http://127.0.0.1:9090/providers/proxies/Provider%20A" . "GET")
                    requests))))

(provide 'mihomo-rules-test)
;;; mihomo-rules-test.el ends here
