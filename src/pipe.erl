%%
%%   Copyright (c) 2012 - 2013, Dmitry Kolesnikov
%%   Copyright (c) 2012 - 2013, Mario Cardona
%%   All Rights Reserved.
%%
%%   Licensed under the Apache License, Version 2.0 (the "License");
%%   you may not use this file except in compliance with the License.
%%   You may obtain a copy of the License at
%%
%%       http://www.apache.org/licenses/LICENSE-2.0
%%
%%   Unless required by applicable law or agreed to in writing, software
%%   distributed under the License is distributed on an "AS IS" BASIS,
%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%   See the License for the specific language governing permissions and
%%   limitations under the License.
%%
%% @description
%%
-module(pipe).
-include("pipe.hrl").

-export([start/0]).
-export([behaviour_info/1]).
%% pipe management interface
-export([
   start/3,
   start/4,
   start_link/3,
   start_link/4,
   supervise/2,
   supervise/3,
   supervise/4,
   spawn/1,
   spawn_link/1,
   spawn_link/2,
   fspawn/1,
   fspawn_link/1,
   fspawn_link/2,
   head/1,
   tail/1,
   element/2,
   bind/2,
   bind/3,
   make/1,
   make/2,
   free/1,
   monitor/1,
   monitor/2,
   demonitor/1,
   ioctl/2,
   ioctl_/2
]).
%% pipe i/o interface
-export([
   call/2,
   call/3,
   cast/2,
   cast/3,
   send/2,
   send/3,
   emit/3,
   emit/4,
   ack/2,
   recv/0, 
   recv/1,
   recv/2,
   recv/3,
   a/1,
   a/2, 
   a/3,
   b/1,
   b/2,
   b/3,
   pid/1,
   tx/1,
   swap/1
]).

%%%------------------------------------------------------------------
%%%
%%% data types
%%%
%%%------------------------------------------------------------------   
-export_type([pipe/0, fpipe/0, fpure/0]).

%%
%% The pipe is opaque data structure maintained by pipe process.
%% It is used by state machine behavior to emit side-effect.
-type pipe()  :: {pipe, a(), b()}.
-type a()     :: pid() | tx().
-type b()     :: pid().
-type tx()    :: {pid(), reference()} | {reference(), pid()}.

%%
%% pipe lambda expression is spawned within pipe process.
%% It builds a new message by applying a function to all received message.
%% The process emits the new message either to side (a) or (b). 
-type fpipe() :: fun((_) -> {a, _} | {b, _} | _).
-type fpure() :: fun((_) -> undefined | _).

%%
%% the process monitor structure 
-type monitor() :: {reference(), pid() | node()}.

 
%%%------------------------------------------------------------------
%%%
%%% pipe behavior interface
%%%
%%%------------------------------------------------------------------   

%%
%% pipe behavior
behaviour_info(callbacks) ->
   [
      %%
      %% init pipe
      %%
      %% The function is called whenever the state machine process is started using either 
      %% start_link or start function. It build internal state data structure, defines 
      %% initial state transition, etc. The function should return either `{ok, Sid, State}` 
      %% or `{error, Reason}`.
      %%
      %% -spec(init/1 :: ([_]) -> {ok, sid(), state()} | {stop, any()}).
      {init,  1},
   
      %%
      %% free pipe stage
      %%
      %% The function is called to release resource owned by state machine, it is called when 
      %% the process is about to terminate.
      %%
      %% -spec(free/2 :: (_, state()) -> ok).
      {free,  2}

      %%
      %% state machine i/o control interface (optional)
      %%
      %% -spec(ioctl/2 :: (atom() | {atom(), _}, state()) -> _ | state()).       
      %%{ioctl, 2}

      %%
      %% state message handler
      %%
      %% The state transition function receive any message, which is sent using pipe interface 
      %% or any other Erlang message passing operation. The function executes the state 
      %% transition, generates output or terminate execution. 
      %%
      %% -spec(handle/3 :: (_, pipe(), state()) -> {next_state, sid(), state()} 
      %%                                           |  {stop, _, state()} 
      %%                                           |  {upgrade, atom(), [_]}). 
   ];
behaviour_info(_Other) ->
   undefined.


%%
%% RnD application start
start() ->
   application:start(pipe).


%%%------------------------------------------------------------------
%%%
%%% factory interface
%%%
%%%------------------------------------------------------------------   

%%
%% start pipe state machine, the function takes behavior module,
%% list of arguments to pipe init functions and list of container options.
-spec start(atom(), [_], [_]) -> {ok, pid()} | {error, _}.
-spec start(atom(), atom(), list(), list()) -> {ok, pid()} | {error, _}.
-spec start_link(atom(), list(), list()) -> {ok, pid()} | {error, _}.
-spec start_link(atom(), atom(), list(), list()) -> {ok, pid()} | {error, _}.

start(Mod, Args, Opts) ->
   gen_server:start(?CONFIG_PIPE, [Mod, Args], Opts).
start(Name, Mod, Args, Opts) ->
   gen_server:start(Name, ?CONFIG_PIPE, [Mod, Args], Opts).

start_link(Mod, Args, Opts) ->
   gen_server:start_link(?CONFIG_PIPE, [Mod, Args], Opts).
start_link(Name, Mod, Args, Opts) ->
   gen_server:start_link(Name, ?CONFIG_PIPE, [Mod, Args], Opts).


%%
%% start supervise-able pipeline
-spec supervise(atom(), [_]) -> {ok, pid()} | {error, any()}.

supervise(Mod, Args) ->
   pipe_supervisor:start_link(Mod, Args, []).


supervise(pipe, Strategy, Spec) ->
   pipe_supervisor:start_link(
      pipe_supervisor_identity, 
      [Strategy, [{pipe, spawn_link, [X]} || X <- Spec]],
      []
   );

supervise(pure, Strategy, Spec) ->
   pipe_supervisor:start_link(
      pipe_supervisor_identity, 
      [Strategy, [{pipe, fspawn_link, [X]} || X <- Spec]],
      []
   );

supervise(Mod, Args, Opts) ->
   pipe_supervisor:start_link(Mod, Args, Opts).


supervise(pipe, Strategy, Spec, Opts) ->
   pipe_supervisor:start_link(
      pipe_supervisor_identity, 
      [Strategy, [{pipe, spawn_link, [X]} || X <- Spec]],
      Opts
   );

supervise(pure, Strategy, Spec, Opts) ->
   pipe_supervisor:start_link(
      pipe_supervisor_identity, 
      [Strategy, [{pipe, fspawn_link, [X]} || X <- Spec]],
      Opts
   ).

%%
%% spawn pipe lambda expression, pipe lambda is a function that
%%   fun/1 :: (_) -> {a, _} | {b, _} | _
-spec spawn(fpipe()) -> {ok, pid()} | {error, _}.
-spec spawn_link(fpipe()) -> {ok, pid()} | {error, _}.
-spec spawn_link(fpipe(), [_]) -> {ok, pid()} | {error, _}.

spawn(Fun) ->
   start(pipe_lambda, [Fun], []).

spawn_link(Fun) ->
   pipe:spawn_link(Fun, []).

spawn_link(Fun, Opts) ->
   start_link(pipe_lambda, [Fun], Opts).

%%
%% spawn a pure function within a pipe, a pure function takes input and produces output
%%   fun/1 :: (_) -> undefined | _
-spec fspawn(fpure()) -> {ok, pid()} | {error, _}.
-spec fspawn_link(fpure()) -> {ok, pid()} | {error, _}.
-spec fspawn_link(fpure(), [_]) -> {ok, pid()} | {error, _}.

fspawn(Fun) ->
   pipe:spawn(fun(X) -> {b, Fun(X)} end).

fspawn_link(Fun) ->
   pipe:spawn_link(fun(X) -> {b, Fun(X)} end).

fspawn_link(Fun, Opts) ->
   pipe:spawn_link(fun(X) -> {b, Fun(X)} end, Opts).

%%
%% terminate pipe or pipeline
-spec free(pid() | [pid()]) -> ok.

free(Pid)
 when is_pid(Pid) ->
   pipe:call(Pid, '$free');
free(Pipeline)
 when is_list(Pipeline) ->
   lists:foreach(fun free/1, Pipeline).

%%%------------------------------------------------------------------
%%%
%%% connectivity interface
%%%
%%%------------------------------------------------------------------   

%%
%% return head of supervised pipeline 
-spec head(pid()) -> pid().

head(Sup) ->
   erlang:element(2,
      hd(supervisor:which_children(Sup))
   ).

%%
%% return tail of supervised pipeline 
-spec tail(pid()) -> pid().

tail(Sup) ->
   erlang:element(2,
      lists:last(supervisor:which_children(Sup))
   ).

%%
%% return nth element of supervised pipeline
-spec element(integer(), pid()) -> pid().

element(Nth, Sup) ->
   erlang:element(2,
      lists:keyfind(Nth, 1, 
         supervisor:which_children(Sup)
      )
   ).

%%
%% bind stage(s) together defining processing pipeline
-spec bind(a | b, pid()) -> {ok, pid()}.
-spec bind(a | b, pid(), pid()) -> {ok, pid()}.

bind(a, Pids)
 when is_list(Pids) ->
   bind(a, hd(Pids));
bind(b, Pids)
 when is_list(Pids) ->
   bind(b, lists:last(Pids)); 

bind(a, Pid) ->
   ioctl_(Pid, {a, self()});
bind(b, Pid) ->
   ioctl_(Pid, {b, self()}).

bind(a, Pids, A)
 when is_list(Pids) ->
   bind(a, hd(Pids), A);
bind(b, Pids, A)
 when is_list(Pids) ->
   bind(b, lists:last(Pids), A);

bind(a, Pid, A) ->
   ioctl_(Pid, {a, A});
bind(b, Pid, B) ->
   ioctl_(Pid, {b, B}).

%%
%% make pipeline by binding stages
%% Options:
%%   * join_side_a - join a process to pipeline on side a (head)
%%   * join_side_b - join a process to pipeline on side b (tail)
%%   * heir_side_a - heir process receives results of pipeline at side a
%%   * heir_side_b - heir process receives results of pipeline at side b
%%   * capacity - set capacity of flow control buffers
%%
-spec make([pid()]) -> [pid()].
-spec make([pid()], [_]) -> [pid()].

make(Stages) ->
   make(Stages, []).

make(Stages, Opts) ->
   heir_sides(option(heir_side_a, Opts), option(heir_side_b, Opts),
      disjoin_sides(option(join_side_a, Opts), option(join_side_b, Opts),
         link_pipe(
            join_sides(option(join_side_a, Opts), option(join_side_b, Opts),
               capacity(option(capacity, Opts), Stages)
            )
         )
      )
   ).

option(Key, Opts) ->
   proplists:get_value(Key, Opts).

%%
capacity(undefined, Stages) ->
   Stages;
capacity(Capacity, Stages) ->
   [pipe:ioctl_(Pid, {capacity, Capacity}) || Pid <- Stages],
   Stages.

%%
join_sides(undefined, undefined, Stages) ->
   Stages;
join_sides(SideA, undefined, Stages) ->
   [SideA | Stages];
join_sides(undefied, SideB, Stages) ->
   Stages ++ [SideB];
join_sides(SideA, SideB, Stages) ->
   [SideA | Stages] ++ [SideB].

%%
disjoin_sides(undefined, undefined, Stages) ->
   Stages;
disjoin_sides(SideA, undefined, [SideA | Stages]) ->
   Stages;
disjoin_sides(undefied, SideB, Stages) ->
   Stages -- [SideB];
disjoin_sides(SideA, SideB, [SideA | Stages]) ->
   [SideA | Stages] -- [SideB].


%%
link_pipe(Stages) ->
   [Head | Tail] = lists:reverse(Stages),
   lists:foldl(
      fun(Sink, Source) -> 
         {ok, _} = bind(b, Sink, Source),
         {ok, _} = bind(a, Source, Sink),
         Sink
      end, 
      Head,
      Tail
   ),
   Stages.

%%
heir_sides(undefined, undefined, Stages) ->
   Stages;
heir_sides(SideA, undefined, Stages) ->
   pipe:bind(a, hd(Stages), SideA),
   Stages;
heir_sides(undefined, SideB, Stages) ->
   pipe:bind(b, lists:last(Stages), SideB),
   Stages;
heir_sides(SideA, SideB, Stages) ->
   pipe:bind(a, hd(Stages), SideA),
   pipe:bind(b, lists:last(Stages), SideB),
   Stages.

%%%------------------------------------------------------------------
%%%
%%% management interface
%%%
%%%------------------------------------------------------------------   

%%
%% ioctl interface (sync and async)
-spec ioctl(pid(), atom() | {atom(), any()}) -> any().
-spec ioctl_(pid(), atom() | {atom(), any()}) -> any().

ioctl(Pid, {Req, Val})
 when is_atom(Req) ->
   call(Pid, {ioctl, Req, Val}, infinity);
ioctl(Pid, Req)
 when is_atom(Req) ->
   call(Pid, {ioctl, Req}, infinity).

ioctl_(Pid, {Req, Val})
 when is_atom(Req) ->
   send(Pid, {ioctl, Req, Val}), 
   {ok, Val}.


%%
%% The helper function to monitor either Erlang process or Erlang node. 
%% The caller process receives one of following messages:
%%   {'DOWN', reference(), process, pid(), reason()}
%%   {nodedown, node()}
-spec monitor(pid()) -> monitor().
-spec monitor(atom(), pid()) -> monitor().

monitor(undefined) ->
   ok;
monitor(Pid) ->
   pipe:monitor(process, Pid).

monitor(process, Pid) ->
   try erlang:monitor(process, Pid) of
      Ref ->
         {process, Ref, Pid}
   catch error:_ ->
      % unable to set monitor, fall-back to node monitor
      pipe:monitor(node, erlang:node(Pid))
   end;

monitor(node, Node) ->
   erlang:monitor_node(Node, true),
   {node, erlang:make_ref(), Node}.
 
%%
%% release process monitor
-spec demonitor(monitor()) -> ok.

demonitor({process, Ref, _Pid}) ->
   erlang:demonitor(Ref, [flush]);

demonitor({node, _, Node}) ->
   erlang:monitor_node(Node, false),
   receive
      {nodedown, Node} -> 
         ok
   after 0 ->
      ok 
   end.

%%%------------------------------------------------------------------
%%%
%%% i/o interface
%%%
%%%------------------------------------------------------------------   


%%
%% make synchronous request to pipe.
%% the caller process is blocked until response is received.
-spec call(pid(), _) -> _.
-spec call(pid(), _, timeout()) -> _.

call(Pid, Msg) ->
   call(Pid, Msg, ?CONFIG_TIMEOUT).
call(Pid, Msg, Timeout) ->
   try erlang:monitor(process, Pid) of
      Tx ->
         catch erlang:send(Pid, {'$pipe', {self(), Tx}, Msg}, [noconnect]),
         receive
         {Tx, Reply} ->
            erlang:demonitor(Tx, [flush]),
            Reply;
         {'DOWN', Tx, _, _, noconnection} ->
            exit({nodedown, erlang:node(Pid)});
         {'DOWN', Tx, _, _, Reason} ->
            exit(Reason)
         after Timeout ->
            erlang:demonitor(Tx, [flush]),
            exit(timeout)
         end
   catch error:_ ->
      Tx   = erlang:make_ref(),
      Node = erlang:node(Pid),
      monitor_node(Node, true),
      catch erlang:send(Pid, {'$pipe', {self(), Tx}, Msg}, [noconnect]),
      receive
      {Tx, Reply} ->
         monitor_node(Node, false),
         Reply;
      {nodedown, Node} ->
         exit({nodedown, Node})
      after Timeout ->
         monitor_node(Node, false),
         exit(timeout)
      end
   end.

%%
%% cast asynchronous request to process
%%   Options:
%%      yield     - suspend current processes
%%      noconnect - do not connect to remote node
-spec cast(pid(), _) -> reference().
-spec cast(pid(), _, [atom()]) -> reference().

cast(Pid, Msg) ->
   cast(Pid, Msg, []).

cast(Pid, Msg, Opts) ->
   Tx = erlang:make_ref(),
   pipe_send(Pid, {Tx, self()}, Msg, Opts),
   Tx.

%%
%% send asynchronous request to process 
%%   Options:
%%      yield     - suspend current processes
%%      noconnect - do not connect to remote node
-spec send(pid(), _) -> _.
-spec send(pid(), _, [atom()]) -> _.

send(Pid, Msg) ->
   send(Pid, Msg, []).
send(Pid, Msg, Opts) ->
   pipe_send(Pid, self(), Msg, Opts).

%%
%% forward asynchronous request to destination pipe.
%% the side (a) is preserved and forwarded to destination pipe  
-spec emit(pipe(), pid(), _) -> _.
-spec emit(pipe(), pid(), _, [atom()]) -> _.

emit(Pipe, Pid, Msg) ->
   emit(Pipe, Pid, Msg, []).

emit({pipe, A, _}, Pid, Msg, Opts) ->
   pipe_send(Pid, A, Msg, Opts).

%%
%% asynchronous send message through pipe to side (a)
-spec a(pipe(), _) -> ok.

a({pipe, Pid, _}, Msg)
 when is_pid(Pid) orelse is_atom(Pid) ->
   pipe:send(Pid, Msg);
a({pipe, {Pid, Tx}, _}, Msg)
 when is_pid(Pid), is_reference(Tx) ->
   % backward compatible with gen_server:reply
   try erlang:send(Pid, {Tx, Msg}), Msg catch _:_ -> Msg end;
a({pipe, {Tx, Pid}, _}, Msg)
 when is_pid(Pid), is_reference(Tx) ->
   try erlang:send(Pid, {Tx, Msg}), Msg catch _:_ -> Msg end.

%%
%% synchronous send message through pipe to side (a)
-spec a(pipe(), _, timeout()) -> ok.

a({pipe, Pid, _}, Msg, Timeout) ->
   pipe:call(Pid, Msg, Timeout).

%%
%% asynchronous send message through pipe to side (b)
-spec b(pipe(), _) -> ok.

b({pipe, _, B}, Msg) ->
   pipe:send(B, Msg).

%%
%% synchronous send message through pipe to side (a)
-spec b(pipe(), _, timeout()) -> ok.

b({pipe, _, B}, Msg, Timeout) ->
   pipe:call(B, Msg, Timeout).


%%
%% acknowledge message received at pipe side (a)
-spec ack(pipe() | tx(), _) -> _.

ack({pipe, {_, _} = A, _}, Msg) ->
   pipe:ack(A, Msg);
ack({pipe, _,  _}, Msg) ->
   %% Note: the ack does nothings for pipe operation
   %%       this allows us to compose state-machine to work both 
   %%       as api and intermediate nodes 
   Msg;
ack({Pid, Tx}, Msg)
 when is_pid(Pid), is_reference(Tx) ->
   % backward compatible with gen_server:reply
   try erlang:send(Pid, {Tx, Msg}), Msg catch _:_ -> Msg end;
ack({Pid, [alias|Mref] = Tx}, Msg)
 when is_pid(Pid), is_reference(Mref) ->
   % OTP-24 backward compatible with gen_server:reply
   try erlang:send(Pid, {Tx, Msg}), Msg catch _:_ -> Msg end;
ack({Tx, Pid}, Msg)
 when is_pid(Pid), is_reference(Tx) ->
   try erlang:send(Pid, {Tx, Msg}), Msg catch _:_ -> Msg end;
ack(Pid, Msg)
 when is_pid(Pid) ->
   % no acknowledgment send for transactions originated by send 
   Msg;
ack(_, Msg) ->
   Msg.

%%
%% receive message from pipe (match-only pipe protocol)
%%  Options
%%    noexit - opts returns {error, timeout} instead of exit signal
-spec recv() -> _.
-spec recv(timeout()) -> _.
-spec recv(timeout(), [atom()]) -> _.
-spec recv(pid(), timeout(), [atom()]) -> _.

recv() ->
   recv(5000).

recv(Timeout) ->
   recv(Timeout, []).

recv(Timeout, Opts) ->
   receive
   {'$pipe', _Pid, Msg} ->
      Msg
   after Timeout ->
      recv_error(Opts, timeout)
   end.

recv(Pid, Timeout, Opts) ->
   Tx = erlang:monitor(process, Pid),
   receive
   {'$pipe', Pid, Msg} ->
      erlang:demonitor(Tx, [flush]),
      Msg;
   {'$pipe',   _, {ioctl, _, Pid} = Msg} ->
      erlang:demonitor(Tx, [flush]),
      Msg;      
   {'DOWN', Tx, _, _, noconnection} ->
      erlang:demonitor(Tx, [flush]),
      recv_error(Opts, {nodedown, erlang:node(Pid)});
   {'DOWN', Tx, _, _, Reason} ->
      erlang:demonitor(Tx, [flush]),
      recv_error(Opts, Reason);
   {nodedown, Node} ->
      erlang:demonitor(Tx, [flush]),
      recv_error(Opts, {nodedown, Node})
   after Timeout ->
      recv_error(Opts, timeout)
   end.
   
recv_error([noexit], Reason) ->
   {error, Reason};
recv_error(_, Reason) ->
   exit(Reason).


%%
%% return pid() of pipe processes
-spec a(pipe()) -> pid() | undefined.
-spec b(pipe()) -> pid() | undefined.

a({pipe, {_, A}, _})
 when is_pid(A) -> 
   A;
a({pipe, {A, _}, _})
 when is_pid(A) -> 
   A;
a({pipe, A, _}) ->
   A. 
b({pipe, _, B}) -> 
   B.

%%
%% extract transaction pid
-spec pid(pipe()) -> pid() | undefined.

pid(Pipe) ->
   pipe:a(Pipe).

%%
%% extract transaction reference
-spec tx(pipe()) -> reference() | undefined.

tx({pipe, {_Pid, Tx}, _})
 when is_reference(Tx) ->
   Tx;
tx({pipe, {Tx, _Pid}, _})
 when is_reference(Tx) ->
   Tx;
tx({pipe, _, _}) ->
   undefined.

%%
%% swap pipe direction
-spec swap(pipe()) -> pipe().

swap({pipe, {_, _}, _} = Pipe) ->
   Pipe;
swap({pipe, A, B}) ->
   {pipe, B, A}.

%%%----------------------------------------------------------------------------   
%%%
%%% private
%%%
%%%----------------------------------------------------------------------------   

%%
%% send message through pipe
pipe_send(Pid, Tx, Msg, Opts)
 when ?is_pid(Pid) ->
   try
      pipe_send_msg(Pid, {'$pipe', Tx, Msg}, lists:member(noconnect, Opts)),
      pipe_yield(lists:member(yield, Opts)),
      Msg
   catch error:_ ->
      Msg
   end;
pipe_send(Fun, Tx, Msg, Opts)
 when is_function(Fun) ->
   pipe_send(Fun(Msg), Tx, Msg, Opts).

%%
%% send message to pipe process
pipe_send_msg(Pid, Msg, false) ->
   erlang:send(Pid, Msg, []);
pipe_send_msg(Pid, Msg, true) ->
   erlang:send(Pid, Msg, [noconnect]).

%%
%% yield current process
pipe_yield(false) -> ok;
pipe_yield(true)  -> erlang:yield().





