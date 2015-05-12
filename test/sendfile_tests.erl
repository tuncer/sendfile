%%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ts=4 sw=4 sts=4 et
%%%
%%% Copyright 2010-2015 Tuncer Ayaz. All Rights Reserved.
%%% Use of this source code is governed by a BSD-style
%%% license that can be found in the LICENSE file.

-module(sendfile_tests).
-author(tuncerayaz).
-export([server/1]).

-include_lib("kernel/include/file.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(HOST,"localhost").
-define(TESTFILE,"../test/testfile").
-define(TIMEOUT, 10000).


basic_test_() ->
    {setup,
     fun() -> ok = application:start(sendfile) end,
     fun(_) -> ok = application:stop(sendfile) end,
     ?_test(begin ?assertEqual(ok, send(?HOST, ?TESTFILE)) end)}.

send(Host, File) ->
    {Size, _Md5} = FileInfo = file_info(File),
    spawn_link(?MODULE, server, [self()]),
    receive
        {server, Port} ->
            {ok, Sock} = gen_tcp:connect(Host, Port, [binary, {packet,0}]),
            {ok, Size} = sendfile:send(Sock, File),
            ok = gen_tcp:close(Sock),
            receive
                {ok, Bin} ->
                    FileInfo = bin_info(Bin),
                    ok
            after ?TIMEOUT ->
                    ?assert(failure =:= timeout)
            end
    after ?TIMEOUT ->
            ?assert(failure =:= timeout)
    end.

server(ClientPid) ->
    {ok, LSock} = gen_tcp:listen(0, [binary, {packet, 0},
                                     {active, false},
                                     {reuseaddr, true}]),
    {ok, Port} = inet:port(LSock),
    ClientPid ! {server, Port},
    {ok, Sock} = gen_tcp:accept(LSock),
    {ok, Bin} = do_recv(Sock, []),
    ok = gen_tcp:close(Sock),
    ClientPid ! {ok, Bin}.

do_recv(Sock, Bs) ->
    case gen_tcp:recv(Sock, 0, ?TIMEOUT) of
        {ok, B} ->
            do_recv(Sock, [B|Bs]);
        {error, closed} ->
            {ok, lists:reverse(Bs)}
    end.

file_info(File) ->
    {ok, #file_info{size = Size}} = file:read_file_info(File),
    {ok, Data} = file:read_file(File),
    Md5 = erlang:md5(Data),
    {Size, Md5}.

bin_info(Data) ->
    Size = lists:foldl(fun(E,Sum) -> size(E) + Sum end, 0, Data),
    Md5 = erlang:md5(Data),
    {Size, Md5}.
