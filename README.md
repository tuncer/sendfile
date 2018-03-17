Erlang sendfile() linked-in driver
==================================

*Deprecated: use [file:sendfile](http://www.erlang.org/doc/man/file.html#sendfile-2) (available since OTP R15B)*

**sendfile** is a linked-in driver for the sendfile(2) syscall.

Based on original driver from [yaws](http://yaws.hyber.org).

Building and Installing
-----------------------

sendfile is built with [rebar3](https://github.com/erlang/rebar3/) and we do
expect `rebar3` to be in the search `PATH`. If `rebar3` can not be found in the
search `PATH`, it will be automatically downloaded to `support/rebar3` for local
use.
