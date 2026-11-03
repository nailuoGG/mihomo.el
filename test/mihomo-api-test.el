;;; mihomo-api-test.el --- Tests for Mihomo controller support -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-api)
(require 'mihomo-connections)
(require 'mihomo-proxies)

(defun mihomo-test--json (string)
  "Parse STRING with the same representation as `mihomo-api-request'."
  (json-parse-string string :object-type 'hash-table :array-type 'list
                     :null-object nil :false-object :json-false))

(ert-deftest mihomo-api-parses-success-response ()
  (let ((buffer (generate-new-buffer " *mihomo-api-test*")) result error)
    (with-current-buffer buffer
      (insert "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n"
              "{\"version\":\"1.19.33\",\"meta\":true}")
      (setq-local url-http-response-status 200
                  url-http-end-of-headers
                  (copy-marker (save-excursion
                                 (goto-char (point-min))
                                 (search-forward "\r\n\r\n"))))
      (mihomo-api--handle-response
       nil (lambda (value api-error)
             (setq result value error api-error))))
    (should-not error)
    (should (equal (gethash "version" result) "1.19.33"))
    (should (eq (gethash "meta" result) t))))

(ert-deftest mihomo-api-parses-http-error ()
  (let ((buffer (generate-new-buffer " *mihomo-api-test*")) result error)
    (with-current-buffer buffer
      (insert "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\n\r\n"
              "{\"message\":\"Unauthorized\"}")
      (setq-local url-http-response-status 401
                  url-http-end-of-headers
                  (copy-marker (save-excursion
                                 (goto-char (point-min))
                                 (search-forward "\r\n\r\n"))))
      (mihomo-api--handle-response
       '(:error (error http 401))
       (lambda (value api-error)
         (setq result value error api-error))))
    (should-not result)
    (should (= (plist-get error :status) 401))
    (should (equal (plist-get error :message) "Unauthorized"))))

(ert-deftest mihomo-api-reads-secret-from-auth-source ()
  (let (arguments)
    (cl-letf (((symbol-function 'auth-source-search)
               (lambda (&rest args)
                 (setq arguments args)
                 (list (list :secret (lambda () "auth-secret"))))))
      (let ((mihomo-controller-url "http://controller.example:9090"))
        (should (equal (mihomo-api--secret) "auth-secret"))))
    (should (equal (plist-get arguments :host) "controller.example"))
    (should (equal (plist-get arguments :port) "9090"))
    (should (equal (plist-get arguments :user) "mihomo"))))

(ert-deftest mihomo-api-builds-authenticated-selector-request ()
  (let (captured-url captured-method captured-data captured-headers)
    (cl-letf (((symbol-function 'mihomo-api--secret) (lambda () "test-secret"))
              ((symbol-function 'url-retrieve)
               (lambda (url _callback _cbargs &rest _args)
                 (setq captured-url url
                       captured-method url-request-method
                       captured-data url-request-data
                       captured-headers url-request-extra-headers))))
      (let ((mihomo-controller-url "http://127.0.0.1:9090/"))
        (mihomo-api-select-proxy "Group A" "Node B" #'ignore)))
    (should (equal captured-url
                   "http://127.0.0.1:9090/proxies/Group%20A"))
    (should (equal captured-method "PUT"))
    (should (equal (cdr (assoc "Authorization" captured-headers))
                   "Bearer test-secret"))
    (should (equal (json-parse-string captured-data :object-type 'alist)
                   '((name . "Node B"))))))

(ert-deftest mihomo-proxies-builds-group-entries ()
  (let* ((response
          (mihomo-test--json
           "{\"proxies\":{\"Proxy\":{\"type\":\"Selector\",\"now\":\"A\",\"all\":[\"A\",\"B\"]},\"A\":{\"type\":\"Direct\"}}}"))
         (entries (mihomo-proxies--entries response)))
    (should (= (length entries) 1))
    (should (equal (car (car entries)) "Proxy"))
    (should (equal (append (cadr (car entries)) nil)
                   '("Proxy" "Selector" "A" "2")))))

(ert-deftest mihomo-connections-builds-entries ()
  (let* ((response
          (mihomo-test--json
           "{\"connections\":[{\"id\":\"id-1\",\"metadata\":{\"host\":\"example.com\",\"network\":\"tcp\"},\"rule\":\"Match\",\"chains\":[\"Proxy\",\"Node\"],\"upload\":1024,\"download\":2048}]}"))
         (entry (car (mihomo-connections--entries response))))
    (should (equal (car entry) "id-1"))
    (should (equal (aref (cadr entry) 0) "example.com"))
    (should (equal (aref (cadr entry) 3) "Proxy → Node"))))

(provide 'mihomo-api-test)
;;; mihomo-api-test.el ends here
