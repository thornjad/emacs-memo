;;; memo.el --- Memoization library -*- lexical-binding: t; -*-
;;
;; Author: Jade Michael Thornton
;; Copyright (c) 2020 Jade Michael Thornton
;; URL: https://gitlab.com/thornjad/emacs-memo
;; Version: 0.1.0
;;
;; This file is not part of GNU Emacs

;;; Commentary:
;;
;; [![ISC License](https://img.shields.io/badge/license-ISC-green.svg)](./LICENSE) [![](https://img.shields.io/github/languages/code-size/thornjad/emacs-memo.svg)](https://gitlab.com/thornjad/emacs-memo) [![](https://img.shields.io/github/v/tag/thornjad/emacs-memo.svg?label=version&color=yellowgreen)](https://gitlab.com/thornjad/emacs-memo/-/tags)
;;
;; Memo provides easy-to-use macros and functions to memoize other functions.

;; Usage:
;;
;; All of the "creation" functions, `memo-clone', `memo-replace' and
;; `memo-defun' accept a TIMEOUT parameter. If TIMEOUT is non-nil, it specifies
;; the cache invalidation time for the memoized function. The syntax is the same
;; as for `run-at-time', except that if TIMEOUT is 0, the cache will have no
;; invalidation time. Be careful as this can cause memory leaks. If TIMEOUT is
;; nil, `memo-default-cache-timeout' will be used instead.
;;
;; Provided functions and macros:
;;
;; `memo-clone' accepts a function symbol and returns a memoized version of the
;; function. Example:
;;
;;    (setq memoized-expensive-func (memo #'some-expensive-function))
;;
;; `memo-replace' accepts a function symbol and _replaces_ the symbol's
;; function definition with a memoized version. The original function is
;; retained and can be restored with `memo-restore-function'. An optional third
;; parameter, FORGET-ORIGINAL, if non-nil will not retain the original function.
;; This can be useful for saving space when you know you won't need to restore
;; it.
;;
;; `memo-defun' defines a memoized function. The syntax is the same as for
;; `defun', except that the first parameter is a TIMEOUT as specified above:
;;
;;    (memo-defun 100 some-expensive-function (n)
;;      ...body)
;;
;; `memo-restore-function' accepts a symbol of a function which was replaced by
;; `memo-replace' and restores the original non-memoized function.
;;
;; `memo-reset-function-cache' accepts a memoized function symbol and an
;; optional timeout (as specified above) and replaces the function with a
;; version with an empty cache.

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

(defvar memo-default-cache-timeout 60
  "Time after which a cached entry is invalidated.
If this value is an integer, it is interpreted as seconds.

If non-nil, this value represents the amount of time for which to retain a cache
value, after which the entry will be invalidated. Subsequent uses of memoized
functions will then be fully recalculated and entered into the cache anew.

The format for this value is the same as for `run-at-time', except that if the
value is 0 or nil, the cache will have an infinite cache time. This can cause
memory leaks if used improperly.

The default cache time is 60 seconds.")

(defun memo-clone (func &optional timeout)
  "Create a memoized clone of FUNC with an optional cache TIMEOUT.
Given a FUNC symbol, returns a memoized version of that function.

If TIMEOUT is non-nil, it specifies the cache invalidation time for the memoized
function. The syntax is the same as for `run-at-time', except that if TIMEOUT is
0, the cache will have no invalidation time. Be careful as this can cause memory
leaks. If TIMEOUT is nil, `memo-default-cache-timeout' will be used instead.

Returns the memoized clone of FUNC."
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
                (new-timeout (or timeout
                                 memo-default-cache-timeout
                                 0)))
            ;; override any existing timeout for these args
            (when existing-timer
              (cancel-timer existing-timer))
            (when (and new-timeout (> new-timeout 0))
              (puthash args (run-at-time new-timeout nil
                                         (lambda () (remhash args cache)))
                       timeouts))))))))

(defun memo-replace (func &optional timeout forget-original)
  "Replace function FUNC with a memoized version with TIMEOUT.
The function definition for the symbol FUNC will be swapped for a memoized
version. The non-memoized version will be retained and can be restored with
`memo-restore-function'.

If TIMEOUT is non-nil, it specifies the cache invalidation time for the memoized
function. The syntax is the same as for `run-at-time', except that if TIMEOUT is
0, the cache will have no invalidation time. Be careful as this can cause memory
leaks. If TIMEOUT is nil, `memo-default-cache-timeout' will be used instead.

If FORGET-ORIGINAL is non-nil, do not save the original non-memoized function
definition. The resulting function cannot be restored by
`memo-restore-function'. This option will avoid unnecessary memory usage when
restoration will not be needed.

It is an error to attempt to `memo-replace' the same function more than once,
since this doesn't really make sense.

Also returns the now-memoized function definition, for good measure."
  (when (get func :memo-original-function)
    (user-error "%s is already memoized" func))
  (let ((doc (documentation func)))
    (unless forget-original
      (put func :memo-original-documentation doc)
      (put func :memo-original-function (symbol-function func)))
    (put func 'function-documentation
         (concat doc "\n\nThis function is memoized by `memo-replace'.")))
  (fset func (memo-clone func timeout)))

(defun memo-restore-function (func)
  "Restore the original version of the memoized FUNC."
  (let ((original (get func :memo-original-function)))
    (unless original
      (user-error "%s does not have a non-memoized function definition stored" func))
    (fset func original))
  (put func :memo-original-function nil)
  (put func 'function-documentation (get func :memo-original-documentation))
  (put func ':memo-original-documentation nil))

(defun memo-reset-function-cache (func &optional timeout)
  "Reset FUNC's memoization cache with TIMEOUT.

WARNING: If FUNC was not already memoized, this function will memoize it without
the ability to restore the original.

If TIMEOUT is non-nil, it specifies the cache invalidation time for the memoized
function. The syntax is the same as for `run-at-time', except that if TIMEOUT is
0, the cache will have no invalidation time. Be careful as this can cause memory
leaks. If TIMEOUT is nil, `memo-default-cache-timeout' will be used instead.

WARNING: If TIMEOUT is nil, the default `memo-default-cache-timeout' will be
used, not the function's original timeout."
  (memo-replace func timeout t))

;; TODO can we use cl to get :timeout into a tag format?
(defmacro memo-defun (timeout name args &rest body)
  "Create memoized func with TIMEOUT using NAME, ARGS, BODY with `defun' syntax.

If TIMEOUT is non-nil, it specifies the cache invalidation time for the memoized
function. The syntax is the same as for `run-at-time', except that if TIMEOUT is
0, the cache will have no invalidation time. Be careful as this can cause memory
leaks. If TIMEOUT is nil, `memo-default-cache-timeout' will be used instead.

NAME, ARGS and BODY are used to define the function with the same syntax as
`defun'."
  (declare (indent defun) (doc-string 3) (debug defun))
  `(progn (defun ,name ,args ,@body)
          (memo-replace (quote ,name) ,timeout t)))

(provide 'memo)

;;; memo.el ends here
