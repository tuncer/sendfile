%%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ts=4 sw=4 sts=4 et
%%%
%%% Copyright 2008-2014 Steve Vinoski. All Rights Reserved.
%%% Copyright 2010-2014 Tuncer Ayaz. All Rights Reserved.
%%% Use of this source code is governed by a BSD-style
%%% license that can be found in the LICENSE file.
%%%
%%% Based on original code from yaws
%%%
%%% File    : yaws_sendfile.erl
%%% Author  : Claes Wikstrom, klacke@hyber.org
%%%           Steve Vinoski, vinoski@ieee.org
%%% Description : Conditional OS dependent call to sendfile
%%%
%%% Renamed to sendfile and modified: Tuncer Ayaz in May 2010

-module(sendfile).

-behaviour(gen_server).

-define(SERVER, ?MODULE).

%% TODO: maybe expose as app-config
-define(CHUNK_SIZE, 10240).

-include_lib("kernel/include/file.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0, stop/0, send/2, send/3, send/4, enabled/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:cast(?SERVER, stop).

send(Out, Filename) ->
    send(Out, Filename, 0, all).
send(Out, Filename, Offset) ->
    send(Out, Filename, Offset, all).
send(Out, Filename, Offset, Count) ->
    Count1 = case Count of
                 all ->
                     case file:read_file_info(Filename) of
                         {ok, #file_info{size = Size}} ->
                             Size - Offset;
                         Error ->
                             Error
                     end;
                 Count when is_integer(Count) ->
                     Count;
                 _ ->
                     {error, badarg}
             end,
    case Count1 of
        {error, _}=Error2 ->
            Error2;
        _ ->
            case prim_inet:getfd(Out) of
                {ok, SocketFd} ->
                    do_send(Out, SocketFd, Filename, Offset, Count1);
                Error3 ->
                    Error3
            end
    end.

-ifdef(HAVE_SENDFILE).
enabled() ->
    true.
-else.
enabled() ->
    false.
-endif.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

%% Will be defined for Linux, FreeBSD, DragonflyBSD, Solaris and Mac OS X
-ifdef(HAVE_SENDFILE).

-record(state, {
          port,               % driver port
          caller_tbl          % table mapping socket descriptors to callers
         }).

init([]) ->
    process_flag(trap_exit, true),
    Shlib = "sendfile_drv",
    Dir = code:priv_dir(?MODULE),
    case erl_ddll:load_driver(Dir, Shlib) of
        ok -> ok;
        {error, already_loaded} -> ok;
        _ -> exit({error, "could not load driver " ++ Shlib})
    end,
    Port = open_port({spawn, Shlib}, [binary]),
    CallerTable = ets:new(sendfile_drv, []),
    {ok, #state{port = Port, caller_tbl = CallerTable}}.

handle_call({send, SocketFd, Msg}, From, State) ->
    true = erlang:port_command(State#state.port, Msg),
    true = ets:insert(State#state.caller_tbl, {SocketFd, From}),
    {noreply, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_info({_, {data, <<Cnt:64, SocketFd:32, Res:8, Err/binary>>}}, State) ->
    Reply = case Res of
                1 ->
                    {ok, Cnt};
                0 ->
                    {error,
                     list_to_atom(
                       lists:takewhile(fun(El) -> El =/= 0 end,
                                       binary_to_list(Err)))}
            end,
    CallerTable = State#state.caller_tbl,
    [{SocketFd, From}] = ets:lookup(CallerTable, SocketFd),
    gen_server:reply(From, Reply),
    ets:delete(CallerTable, SocketFd),
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{port = Port, caller_tbl = CallerTable}) ->
    erlang:port_close(Port),
    receive {'EXIT', Port, _Reason} -> ok
    after 0 -> ok
    end,
    ets:delete(CallerTable),
    ok.

-else.

init(Args) ->
    {ok, Args}.

handle_call(_Request, _From, State) ->
    {noreply, ok, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.
-endif.

handle_cast(stop, State) ->
    {stop, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

-ifdef(HAVE_SENDFILE).
do_send(_Out, _SocketFd, _Filename, _Offset, Count) when Count =< 0 ->
    {ok, 0};
do_send(Out, SocketFd, Filename, Offset, Count) ->
    Call = list_to_binary([<<Offset:64, Count:64, SocketFd:32>>,
                           Filename, <<0:8>>]),
    case gen_server:call(?SERVER, {send, SocketFd, Call}, infinity) of
        {error, eoverflow} ->
            compat_send(Out, Filename, Offset, Count);
        Else ->
            Else
    end.
-else.
do_send(_Out, _SocketFd, _Filename, _Offset, Count) when Count =< 0 ->
    {ok, 0};
do_send(Out, _SocketFd, Filename, Offset, Count) ->
    compat_send(Out, Filename, Offset, Count).
-endif.

compat_send(Out, Filename, Offset, Count0) ->
    Count = case Count0 of
                0 -> all;
                _ -> Count0
            end,
    case file:open(Filename, [read, binary, raw]) of
        {ok, Fd} ->
            {ok, _} = file:position(Fd, {bof, Offset}),
            ChunkSize = ?CHUNK_SIZE,
            Ret = loop_send(Fd, ChunkSize, file:read(Fd, ChunkSize), Out,
                            Count, 0),
            ok = file:close(Fd),
            Ret;
        Err ->
            Err
    end.

loop_send(Fd, ChunkSize, {ok, Bin}, Out, all, BytesSent) ->
    case gen_tcp:send(Out, Bin) of
        ok ->
            loop_send(Fd, ChunkSize, file:read(Fd, ChunkSize), Out, all,
                      BytesSent+size(Bin));
        Err ->
            Err
    end;
loop_send(_Fd, _ChunkSize, eof, _Out, _, BytesSent) ->
    {ok, BytesSent};
loop_send(Fd, ChunkSize, {ok, Bin}, Out, Count, BytesSent) ->
    Sz = size(Bin),
    if Sz < Count ->
            case gen_tcp:send(Out, Bin) of
                ok ->
                    loop_send(Fd, ChunkSize, file:read(Fd, ChunkSize),
                              Out, Count-Sz, BytesSent+Sz);
                Err ->
                    Err
            end;
       Sz == Count ->
            case gen_tcp:send(Out, Bin) of
                ok  -> {ok, BytesSent+Sz};
                Err -> Err
            end;
       Sz > Count ->
            <<Deliver:Count/binary , _/binary>> = Bin,
            case gen_tcp:send(Out, Deliver) of
                ok  -> {ok, BytesSent+Count};
                Err -> Err
            end
    end;
loop_send(_Fd, _, Err, _, _, _) ->
    Err.
