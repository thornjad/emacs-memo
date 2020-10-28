# memo - Memoization library

_Author:_ Jade Michael Thornton<br>
_Version:_ 0.1.0<br>

[![ISC License](https://img.shields.io/badge/license-ISC-green.svg)](./LICENSE) [![](https://img.shields.io/github/languages/code-size/thornjad/emacs-memo.svg)](https://gitlab.com/thornjad/emacs-memo) [![](https://img.shields.io/github/v/tag/thornjad/emacs-memo.svg?label=version&color=yellowgreen)](https://gitlab.com/thornjad/emacs-memo/-/tags)

Memo provides easy-to-use macros and functions to memoize other functions.

## Usage

All of the "creation" functions, `memo-clone`, `memo-replace` and
`memo-defun` accept a TIMEOUT parameter. If TIMEOUT is non-nil, it specifies
the cache invalidation time for the memoized function. The syntax is the same
as for `run-at-time`, except that if TIMEOUT is 0, the cache will have no
invalidation time. Be careful as this can cause memory leaks. If TIMEOUT is
nil, `memo-default-cache-timeout` will be used instead.

### Provided functions and macros

`memo-clone` accepts a function symbol and returns a memoized version of the
function. Example:

       (setq memoized-expensive-func (memo #'some-expensive-function))

`memo-replace` accepts a function symbol and _replaces_ the symbol's
function definition with a memoized version. The original function is
retained and can be restored with `memo-restore-function`. An optional third
parameter, FORGET-ORIGINAL, if non-nil will not retain the original function.
This can be useful for saving space when you know you won't need to restore
it.

`memo-defun` defines a memoized function. The syntax is the same as for
`defun`, except that the first parameter is a TIMEOUT as specified above:

       (memo-defun 100 some-expensive-function (n)
         ...body)

`memo-restore-function` accepts a symbol of a function which was replaced by
`memo-replace` and restores the original non-memoized function.

`memo-reset-function-cache` accepts a memoized function symbol and an
optional timeout (as specified above) and replaces the function with a
version with an empty cache.

## Limitations

Currently, memoizing an interactive function will render that function
non-interactive. This is an as-of-yet unsolved issue with byte-compilation.
Luckily for now, interactive functions typically do not lend themselves to
being memoized in the first place.

Also, there is currently no way to memoize when a function returns nil.

Memoization takes up memory, which should be freed at some point. By default,
there is no cache invalidation timeout, since in theory, memoization is
forever. This default is set by `memo-default-cache-timeout`, and can also
be overridden by the `memo` and `memo-replace` functions.

If you wait to byte-compile the function until *after* it is memoized then
the function and memoization wrapper both get compiled at once, so there's no
special reason to do them separately. But there really isn't much advantage
to compiling the memoization wrapper anyway.


---
Converted from `memo.el` by [_el2md_](https://gitlab.com/thornjad/el2md).
