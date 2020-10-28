;;; memo.el --- Memoization library -*- lexical-binding: t; -*-
;;
;; Author: Jade Michael Thornton
;; Copyright (c) 2020 Jade Michael Thornton
;; URL: https://gitlab.com/thornjad/emacs-memo
;; Version: 0.9.0
;;
;; This file is not part of GNU Emacs

;;; Commentary:
;;
;; Memo provides easy-to-use macros and functions to memoize other functions.

;; Usage:
;;
;; `memo' accepts a function symbol and returns a memoized version of the
;; function. Example:
;;
;;    (memo #'some-expensive-function) => memoized version of some-expensive-func
;;
;; `memo-replace' accepts a function symbol and _replaces_ the symbol's
;; function definition with a memoized version. The original function is
;; retained and can be restored with `memo-restore-function'.
;;
;; `memo-defun' defines a memoized function. The syntax is the same as for
;; `defun':
;;
;;    (memo-defun some-expensive-function (n)
;;      ...body)

;; Limitations:
;;
;; Currently, memoizing an interactive function will render that function
;; non-interactive. This is an as-of-yet unsolved issue with byte-compilation.
;; Luckily for now, interactive functions typically do not lend themselves to
;; being memoized in the first place.
;;
;; Also, there is currently no way to memoize when a function returns nil.
;;
;; Memoization takes up memory, which should be freed at some point. By default,
;; there is no cache invalidation timeout, since in theory, memoization is
;; forever. This default is set by `memo-default-cache-timeout', and can also
;; be overridden by the `memo' and `memo-replace' functions.
;;
;; If you wait to byte-compile the function until *after* it is memoized then
;; the function and memoization wrapper both get compiled at once, so there's no
;; special reason to do them separately. But there really isn't much advantage
;; to compiling the memoization wrapper anyway.

;;; License:
;;
;; Copyright (c) 2020 Jade Michael Thornton
;;
;; Permission to use, copy, modify, and/or distribute this software for any
;; purpose with or without fee is hereby granted, provided that the above
;; copyright notice and this permission notice appear in all copies.
;;
;; The software is provided "as is" and the author disclaims all warranties with
;; regard to this software including all implied warranties of merchantability
;; and fitness. In no event shall the author be liable for any special, direct,
;; indirect, or consequential damages or any damages whatsoever resulting from
;; loss of use, data or profits, whether in an action of contract, negligence or
;; other tortious action, arising out of or in connection with the use or
;; performance of this software.

;;; Code:
;; TODO should have a way to clear cache without restoring functions.
(defvar memo-default-cache-timeout nil
  "Time after which a memoization is invalidated.
Any non-nil value represents the time after the last use of a memoization, after
which the value in the cache is invalidated. Subsequent uses of the memoized
functions will be fully recacalculated and entered into the cache anew.

A nil value represents an infinite cache time. This is the default, but can be
misused to cause memory leaks.")

;; TODO ensure the old function is really gone?
(defun memo (func &optional timeout)
  "Create a memoized version of FUNC with an optional cache TIMEOUT.
Given a FUNC symbol, returns a memoized version of that function.

If TIMEOUT is a number, it specifies the cache invalidation time for the
memoized function. If TIMEOUT is 0, the cache will be infinite, which may cause
memory leaks. If TIMEOUT is nil or not a number, `memo-default-cache-timeout'
will be used."
  (let ((cache (make-hash-table :test 'equal))
        (timeouts (make-hash-table :test 'equal)))
    (lambda (&rest args)
      (let ((value (gethash args cache)))
        ;; If storing the function result were to fail, we still want to reset
        ;; the timer for these args
        (unwind-protect
            ;; if there's no cached val, execute func and store result
            (or value (puthash args (apply func args) cache))
          (let ((existing-timer (gethash args timeouts))
                (new-timeout (or (when (numberp timeout) timeout)
                                 memo-default-cache-timeout
                                 0)))
            ;; override any existing timeout for these args
            (when existing-timer
              (cancel-timer existing-timer))
            (when (and new-timeout (> new-timeout 0))
              (puthash args (run-at-time new-timeout nil
                                         (lambda () (remhash args cache)))
                       timeouts))))))))

(defun memo-replace (func &optional timeout)
  "Replace function FUNC with a memoized version with TIMEOUT.
The function definition for the symbol FUNC will be swapped for a memoized
version. The non-memoized version will be retained and can be restored with
`memo-restore-function'.

If TIMEOUT is a number, it specifies the cache invalidation time for the
memoized function. If TIMEOUT is 0, the cache will be infinite, which may cause
memory leaks. If TIMEOUT is nil or not a number, `memo-default-cache-timeout'
will be used.

It is an error to attempt to `memo-replace' the same function more than once,
since this doesn't really make sense.

Also returns the now-memoized function definition, for good measure."
  (when (get func :memo-original-function)
    (user-error "%s is already memoized" func))
  (let ((doc (documentation func)))
    (put func :memo-original-documentation doc)
    (put func 'function-documentation
         (concat doc "\n\nThis function has been memoized. See `memo-replace' to see how it was done.")))
  (put func :memo-original-function (symbol-function func))
  (fset func (memo func timeout)))

(defun memo-restore-function (func)
  "Restore the original version of the memoized FUNC."
  (let ((original (get func :memo-original-function)))
    (unless original
      (user-error "%s does not have a non-memoized function definition stored" func))
    (fset func original))
  (put func :memo-original-function nil)
  (put func 'function-documentation (get func :memo-original-documentation))
  (put func ':memo-original-documentation nil))

(defmacro memo-defun (name args &rest body)
  "Create a memoized function, using NAME, ARGS and BODY with `defun' syntax."
  ;; Internally, since `memo' requires a function symbol, we first define the
  ;; function, then memoize it. The intermediate func is lost and so the user is
  ;; none-the-wiser.
  (declare (indent defun) (doc-string 3) (debug defun))
  `(progn (defun ,name ,args ,@body)
          (memo (quote ,name))))

(provide 'memo)

;;; memo.el ends here
