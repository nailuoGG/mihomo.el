;;; mihomo-api.el --- Mihomo controller API client -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Liu Jiale
;; Author: Liu Jiale
;; Keywords: tools
;; Package-Requires: ((emacs "29.1"))
;; Version: 0.3.0

;;; Commentary:
;; Asynchronous client for the Mihomo external-controller REST API.

;;; Code:

(require 'auth-source)
(require 'json)
(require 'subr-x)
(require 'url)
(require 'url-http)
(require 'url-parse)
(require 'url-util)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

(defcustom mihomo-controller-url "http://127.0.0.1:9090"
  "Base URL of the Mihomo external controller."
  :type 'string
  :group 'mihomo)

(defcustom mihomo-config-file nil
  "Configuration file sent to Mihomo by `mihomo-reload-config'."
  :type '(choice (const :tag "Ask every time" nil) file)
  :group 'mihomo)

(defcustom mihomo-delay-test-url "https://www.gstatic.com/generate_204"
  "URL used for Mihomo proxy delay tests."
  :type 'string
  :group 'mihomo)

(defcustom mihomo-delay-test-timeout 5000
  "Timeout in milliseconds for Mihomo proxy delay tests."
  :type 'integer
  :group 'mihomo)

(defun mihomo-api--secret ()
  "Return the controller secret from auth-source, or nil.
The auth-source entry uses the controller host, port, and user `mihomo'."
  (let* ((url (url-generic-parse-url mihomo-controller-url))
         (host (url-host url))
         (port (or (url-port url)
                   (if (string= (url-type url) "https") 443 80)))
         (entry (car (auth-source-search
                      :host host :port (number-to-string port)
                      :user "mihomo" :require '(:secret) :max 1)))
         (secret (plist-get entry :secret)))
    (when (functionp secret)
      (setq secret (funcall secret)))
    (and (stringp secret) (not (string-empty-p secret)) secret)))

(defun mihomo-api--url (path)
  "Return controller URL for PATH."
  (concat (string-remove-suffix "/" mihomo-controller-url)
          "/" (string-remove-prefix "/" path)))

(defun mihomo-api--error-message (error)
  "Return a display string for controller ERROR."
  (or (plist-get error :message) "Unknown Mihomo controller error"))

(defun mihomo-api-request (method path &optional data callback)
  "Send an asynchronous METHOD request to controller PATH.
Serialize DATA as JSON when non-nil.  Call CALLBACK with two arguments,
RESULT and ERROR.  Exactly one of RESULT and ERROR is non-nil, except that a
successful empty response passes nil for both."
  (let* ((secret (mihomo-api--secret))
         (url-request-method method)
         (url-request-extra-headers
          (append '(("Accept" . "application/json"))
                  (when data '(("Content-Type" . "application/json")))
                  (when secret
                    `(("Authorization" . ,(concat "Bearer " secret))))))
         (url-request-data (and data (encode-coding-string
                                      (json-serialize data) 'utf-8))))
    (url-retrieve
     (mihomo-api--url path)
     #'mihomo-api--handle-response
     (list (or callback #'ignore))
     t t)))

(defun mihomo-api--handle-response (status callback)
  "Parse the current response buffer and call CALLBACK for STATUS."
  (let (result error)
    (unwind-protect
        (condition-case condition
            (let ((network-error (plist-get status :error)))
              (if (and network-error (not url-http-response-status))
                  (setq error
                        `(:type network :message ,(format "%s" network-error)))
                (let ((code url-http-response-status))
                (goto-char url-http-end-of-headers)
                (skip-chars-forward "\r\n")
                (let ((body (buffer-substring-no-properties (point) (point-max))))
                  (when (not (string-empty-p (string-trim body)))
                    (setq result (json-parse-string
                                  body :object-type 'hash-table
                                  :array-type 'list :null-object nil
                                  :false-object :json-false)))
                  (unless (and code (<= 200 code) (< code 300))
                    (setq error
                          `(:type http :status ,code
                            :message ,(or (and (hash-table-p result)
                                               (gethash "message" result))
                                          (format "Mihomo controller returned HTTP %s"
                                                  (or code "unknown")))))
                    (setq result nil))))))
          (error
           (setq error `(:type parse :message ,(error-message-string condition)))))
      (kill-buffer (current-buffer)))
    (funcall callback result error)))

(defun mihomo-api-version (callback)
  "Fetch controller version and call CALLBACK."
  (mihomo-api-request "GET" "/version" nil callback))

(defun mihomo-api-configs (callback)
  "Fetch runtime configuration and call CALLBACK."
  (mihomo-api-request "GET" "/configs" nil callback))

(defun mihomo-api-set-mode (mode callback)
  "Set controller MODE and call CALLBACK."
  (mihomo-api-request "PATCH" "/configs" `((mode . ,mode)) callback))

(defun mihomo-api-reload-config (file callback)
  "Reload absolute configuration FILE and call CALLBACK."
  (let ((path (expand-file-name file)))
    (mihomo-api-request
     "PUT" "/configs?force=true" `((path . ,path)) callback)))

(defun mihomo-api-proxies (callback)
  "Fetch all proxies and groups and call CALLBACK."
  (mihomo-api-request "GET" "/proxies" nil callback))

(defun mihomo-api-select-proxy (group proxy callback)
  "Select PROXY in selector GROUP and call CALLBACK."
  (mihomo-api-request
   "PUT" (concat "/proxies/" (url-hexify-string group))
   `((name . ,proxy)) callback))

(defun mihomo-api-proxy-delay (proxy callback)
  "Test PROXY delay and call CALLBACK."
  (mihomo-api-request
   "GET"
   (concat "/proxies/" (url-hexify-string proxy) "/delay?"
           (url-build-query-string
            `(("url" ,mihomo-delay-test-url)
              ("timeout" ,(number-to-string mihomo-delay-test-timeout)))))
   nil callback))

(defun mihomo-api-connections (callback)
  "Fetch active connections and call CALLBACK."
  (mihomo-api-request "GET" "/connections" nil callback))

(defun mihomo-api-close-connection (id callback)
  "Close connection ID and call CALLBACK."
  (mihomo-api-request
   "DELETE" (concat "/connections/" (url-hexify-string id)) nil callback))

(defun mihomo-api-close-all-connections (callback)
  "Close all active connections and call CALLBACK."
  (mihomo-api-request "DELETE" "/connections" nil callback))

(defun mihomo-api-proxy-providers (callback)
  "Fetch proxy providers and call CALLBACK."
  (mihomo-api-request "GET" "/providers/proxies" nil callback))

(defun mihomo-api-rule-providers (callback)
  "Fetch rule providers and call CALLBACK."
  (mihomo-api-request "GET" "/providers/rules" nil callback))

(defun mihomo-api-update-provider (kind name callback)
  "Update provider NAME of KIND and call CALLBACK.
KIND must be either `proxy' or `rule'."
  (unless (memq kind '(proxy rule))
    (error "Unknown Mihomo provider kind: %s" kind))
  (mihomo-api-request
   "PUT"
   (format "/providers/%s/%s"
           (if (eq kind 'proxy) "proxies" "rules")
           (url-hexify-string name))
   nil callback))

(defun mihomo-api-healthcheck-provider (name callback)
  "Start a health check for proxy provider NAME and call CALLBACK."
  (mihomo-api-request
   "GET"
   (format "/providers/proxies/%s/healthcheck" (url-hexify-string name))
   nil callback))

(provide 'mihomo-api)
;;; mihomo-api.el ends here
