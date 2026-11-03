;;; mihomo-realtime-test.el --- Tests for Mihomo realtime views -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'mihomo-realtime)

(ert-deftest mihomo-realtime-builds-websocket-url ()
  (let ((mihomo-controller-url "https://controller.example:9443/"))
    (should (equal (mihomo-realtime--url "/traffic")
                   "wss://controller.example:9443/traffic"))))

(ert-deftest mihomo-realtime-connects-with-authorization ()
  (let (captured-url captured-arguments closed)
    (cl-letf (((symbol-function 'mihomo-api--secret)
               (lambda () "test-secret"))
              ((symbol-function 'websocket-open)
               (lambda (url &rest arguments)
                 (setq captured-url url captured-arguments arguments)
                 'test-socket))
              ((symbol-function 'websocket-close)
               (lambda (socket) (setq closed socket))))
      (with-temp-buffer
        (let ((mihomo-controller-url "http://127.0.0.1:9090"))
          (mihomo-realtime--connect
           "/traffic" #'ignore #'ignore)
          (should (eq mihomo-realtime--socket 'test-socket))
          (mihomo-realtime-disconnect))))
    (should (equal captured-url "ws://127.0.0.1:9090/traffic"))
    (should (equal (plist-get captured-arguments :custom-header-alist)
                   '(("Authorization" . "Bearer test-secret"))))
    (should (eq closed 'test-socket))))

(ert-deftest mihomo-logs-renders-structured-payload-and-trims ()
  (with-temp-buffer
    (mihomo-logs-mode)
    (let ((mihomo-log-max-lines 2))
      (mihomo-logs--on-message
       "{\"time\":\"12:00:01\",\"level\":\"info\",\"message\":\"first\"}")
      (mihomo-logs--on-message
       "{\"time\":\"12:00:02\",\"level\":\"warning\",\"message\":\"second\"}")
      (mihomo-logs--on-message
       "{\"time\":\"12:00:03\",\"level\":\"error\",\"message\":\"third\"}"))
    (should (= mihomo-logs--line-count 2))
    (should-not (string-match-p "first" (buffer-string)))
    (should (string-match-p "second" (buffer-string)))
    (should (string-match-p "third" (buffer-string)))))

(ert-deftest mihomo-traffic-renders-current-and-total-values ()
  (with-temp-buffer
    (mihomo-traffic-mode)
    (mihomo-traffic--render
     "{\"up\":1024,\"down\":2048,\"upTotal\":4096,\"downTotal\":8192}")
    (should (string-match-p "Upload" (buffer-string)))
    (should (string-match-p "Download" (buffer-string)))
    (should (= (gethash "up" mihomo-traffic--latest) 1024))
    (should (= (gethash "downTotal" mihomo-traffic--latest) 8192))))

(provide 'mihomo-realtime-test)
;;; mihomo-realtime-test.el ends here
