;;; mihomo-providers-test.el --- Tests for Mihomo providers -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-providers)

(defun mihomo-providers-test--json (string)
  "Parse provider JSON STRING."
  (json-parse-string string :object-type 'hash-table :array-type 'list))

(ert-deftest mihomo-providers-builds-proxy-entries ()
  (let* ((response
          (mihomo-providers-test--json
           (concat
            "{\"providers\":{"
            "\"default\":{\"type\":\"Proxy\",\"vehicleType\":\"Compatible\"},"
            "\"Subscription\":{\"type\":\"Proxy\",\"vehicleType\":\"HTTP\","
            "\"updatedAt\":\"2026-11-03T12:00:00Z\",\"proxies\":[{},{}]}}}")))
         (entries (mihomo-providers--entries 'proxy response))
         (entry (car entries)))
    (should (= (length entries) 1))
    (should (equal (car entry) '(proxy . "Subscription")))
    (should (equal (append (cadr entry) nil)
                   '("Proxy" "Subscription" "Proxy" "HTTP"
                     "2026-11-03T12:00:00Z" "2")))))

(ert-deftest mihomo-providers-builds-rule-entries ()
  (let* ((response
          (mihomo-providers-test--json
           "{\"providers\":{\"Rules\":{\"type\":\"Rule\",\"vehicleType\":\"File\",\"updatedAt\":\"2026-11-03T12:00:00Z\",\"ruleCount\":42}}}"))
         (entry (car (mihomo-providers--entries 'rule response))))
    (should (equal (car entry) '(rule . "Rules")))
    (should (equal (aref (cadr entry) 5) "42"))))

(ert-deftest mihomo-api-builds-provider-routes ()
  (let (requests)
    (cl-letf (((symbol-function 'mihomo-api--secret) #'ignore)
              ((symbol-function 'url-retrieve)
               (lambda (url _callback _cbargs &rest _args)
                 (push (cons url url-request-method) requests))))
      (let ((mihomo-controller-url "http://127.0.0.1:9090"))
        (mihomo-api-update-provider 'proxy "Provider A" #'ignore)
        (mihomo-api-update-provider 'rule "Rules A" #'ignore)
        (mihomo-api-healthcheck-provider "Provider A" #'ignore)))
    (should (member '("http://127.0.0.1:9090/providers/proxies/Provider%20A" . "PUT")
                    requests))
    (should (member '("http://127.0.0.1:9090/providers/rules/Rules%20A" . "PUT")
                    requests))
    (should (member '("http://127.0.0.1:9090/providers/proxies/Provider%20A/healthcheck" . "GET")
                    requests))))

(provide 'mihomo-providers-test)
;;; mihomo-providers-test.el ends here
