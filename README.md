Erlang sendfile() linked-in driver
==================================

*Deprecated: use [file:sendfile](http://www.erlang.org/doc/man/file.html#sendfile-2) (available since OTP R15B)*

**sendfile** is a linked-in driver for the sendfile(2) syscall.

Based on original driver from [yaws](http://yaws.hyber.org).

Building and Installing
-----------------------

sendfile is built with [rebar](https://github.com/rebar/rebar/) and we do
expect `rebar` to be in the search `PATH`.  If `rebar` can not be found in the
search `PATH` it will be automatically downloaded to `support/rebar` for local
use.
