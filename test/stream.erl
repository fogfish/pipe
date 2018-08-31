%%
%%   Copyright 2012 - 2013 Dmitry Kolesnikov, All Rights Reserved
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
%% @doc
%%   streams or lazy lists are a sequential data structure that contains 
%%   on demand computed elements. Erlang implementation derived from
%%   scheme stream interface @see http://srfi.schemers.org/srfi-41/srfi-41.html
%%
%%   Note: used ONLY for pipe stream feature testing
%%
-module(stream).

%%
-record(stream, {
   head = undefined :: _,
   tail = undefined :: _
}).
-define(stream(), undefined).
-define(None, undefined).

%%
%% stream primitives - abstract data type 
-export([
   new/0,
   new/1,
   new/2,

   %%
   %% traversable
   head/1,
   tail/1,
   build/1,
   list/1, 
   list/2,
   is_empty/1,
   drop/2,
   dropwhile/2,
   filter/2,
   foreach/2,
   map/2,
   split/2,
   splitwhile/2,
   take/2,
   takewhile/2,

   %%
   %% foldable
   fold/3,
   foldl/3,
   foldr/3,
   unfold/2,

   %%
   %% stream
   '++'/2,
   '++'/1,
   flat/1,
   scan/2,
   scan/3,
   zip/1,
   zip/2,
   zipwith/2,
   zipwith/3,
   reverse/1,
   cycle/1
]).

%%
%% inline stream primitives
-compile({inline,[new/0, new/1, new/2, head/1, tail/1]}).

%%%------------------------------------------------------------------
%%%
%%% stream primitives
%%%
%%%------------------------------------------------------------------

%%
%% creates a newly allocated stream containing stream head and promise.
%% the promise is recursive, it returns new stream pair when evaluated.
-spec new() -> datum:stream(_).
-spec new(_) -> datum:stream(_).
-spec new(_, function()) -> datum:stream(_).

new() ->
   ?None.

new(Head) ->
   new(Head, fun stream:new/0).

new(Head, Fun)
 when is_function(Fun, 0) ->
   #stream{head = Head, tail = Fun};
new(Head, #stream{} = Stream) ->
   #stream{head = Head, tail = fun() -> Stream end};
new(Head, ?None) ->
   new(Head).


%%%------------------------------------------------------------------
%%%
%%% traversable
%%%
%%%------------------------------------------------------------------

%%
%% take collection and return head element of collection
%%
-spec head(datum:traversable(_)) -> datum:option(_).

head(?None) ->
   ?None;
head(#stream{head = Head}) ->
   Head.

%%
%% force stream promise and return new stream (evaluates tail of stream).
-spec tail(datum:traversable(_)) -> datum:traversable(_).

tail(?None) ->
   ?None;
tail(#stream{tail = Fun}) ->
   Fun().

%%
%% build a new collection from Erlang list
%%
-spec build([_] | integer()) -> datum:traversable(_).

build([]) ->
   new();
build([Head|Tail]) ->
   new(Head, fun() -> build(Tail) end);
build(X)
 when is_integer(X) ->
   new(X, fun() -> build(X + 1) end).


%%
%% returns a newly-allocated list containing stream elements
-spec list(datum:stream()) -> list().

list(?None) ->
   [];
list(#stream{} = Stream) ->
   [stream:head(Stream) | list(stream:tail(Stream))].

%%
%% returns a newly-allocated list containing stream elements
-spec list(integer(), datum:stream()) -> list().

list(N, Stream) ->
   list(stream:take(N, Stream)).


%%
%% return true if collection is empty 
%%
-spec is_empty(datum:traversable(_)) -> true | false.

is_empty(?None) ->
   true;
is_empty(#stream{}) ->
   false.


%%
%% returns the suffix of the input stream that starts at the next element after
%% the first n elements.
-spec drop(integer(), datum:stream(_)) -> datum:stream(_).

drop(0, #stream{} = Stream) ->
   Stream;
drop(N, #stream{} = Stream) ->
   drop(N - 1, tail(Stream));
drop(_, ?None) ->
   ?None.

%%
%% drops elements from stream while predicate returns true and returns remaining
%% stream suffix.
-spec dropwhile(datum:predicate(_), datum:stream(_)) -> datum:stream(_).      

dropwhile(Pred, #stream{} = Stream) ->
   case Pred(head(Stream)) of
      true  -> 
         dropwhile(Pred, tail(Stream)); 
      false -> 
         Stream
   end;
dropwhile(_, ?None) ->
   ?None.

%%
%% returns a newly-allocated stream that contains only those elements x of the 
%% input stream for which predicate is true.
-spec filter(datum:predicate(_), datum:stream(_)) -> datum:stream(_).

filter(Pred, #stream{head = Head} = Stream) ->
   case Pred(Head) of
      true -> 
         new(Head, fun() -> filter(Pred, tail(Stream)) end);
      false ->
         filter(Pred, tail(Stream))
   end;
filter(_, ?None) ->
   ?None.

%%
%% applies a function to each stream element for its side-effects; 
%% it returns nothing. 
-spec foreach(function(), datum:stream()) -> ok.

foreach(Fun, #stream{} = Stream) ->
   _ = Fun(head(Stream)),
   foreach(Fun, tail(Stream));
foreach(_, ?None) ->
   ok.


%%
%% create a new stream by apply a function to each element of input stream. 
-spec map(fun((_) -> _), datum:stream(_)) -> datum:stream(_).

map(Fun, #stream{} = Stream) ->
   new(Fun(head(Stream)), fun() -> map(Fun, tail(Stream)) end);
map(_, ?None) ->
   ?None.



%%
%% partitions stream into two streams. The split behaves as if it is defined as 
%% consequent take(N, Stream), drop(N, Stream). 
-spec split(integer(), datum:traversable(_)) -> {datum:traversable(_), datum:traversable(_)}.

split(N, Stream) ->
   split(N, [], Stream).

split(0, Acc, Stream) ->
   {stream:build(lists:reverse(Acc)), Stream};
   
split(N, Acc, #stream{} = Stream) ->
   split(N - 1, [head(Stream)|Acc], tail(Stream));

split(_, Acc, ?None) ->
   {stream:build(lists:reverse(Acc)), ?None}.

%%
%% partitions stream into two streams according to predicate.
%% The splitwith/2 behaves as if it is defined as consequent 
%% takewhile(Pred, Stream), dropwhile(Pred, Stream)
-spec splitwhile(datum:predicate(_), datum:traversable(_)) -> {datum:traversable(_), datum:traversable(_)}.

splitwhile(Pred, Stream) ->
   splitwhile(Pred, [], Stream).

splitwhile(Pred, Acc, #stream{} = Stream) ->
   case Pred(head(Stream)) of
      true  ->
         splitwhile(Pred, [head(Stream)|Acc], tail(Stream));
      false ->
         {stream:build(lists:reverse(Acc)), Stream}
     end;

splitwhile(_, Acc, ?None) ->
   {stream:build(lists:reverse(Acc)), ?None}.


%%
%% returns a newly-allocated stream containing the first n elements of 
%% the input stream. 
-spec take(integer(), datum:traversable(_)) -> datum:traversable(_).

take(0, _) ->
   new();
take(N, #stream{} = Stream) ->
   new(head(Stream), fun() -> take(N - 1, tail(Stream)) end);
take(_, ?None) ->
   ?None.

%%
%% returns a newly-allocated stream that contains those elements from stream 
%% while predicate returns true.
-spec takewhile(datum:predicate(_), datum:traversable(_)) -> datum:traversable(_).

takewhile(Pred, #stream{} = Stream) ->
   case Pred(head(Stream)) of
      true  -> 
         new(head(Stream), fun() -> takewhile(Pred, tail(Stream)) end);
      false ->
         new()
     end;
takewhile(_, ?None) ->
   ?None.

%%%------------------------------------------------------------------
%%%
%%% foldable
%%%
%%%------------------------------------------------------------------

%%
%% applies a function to stream head and accumulator to compute a new accumulator,
%% then applies the function to the new accumulator and the next element of stream to 
%% compute a succeeding accumulator, and so on, the final accumulated value is returned
%% when the end of the stream is reached. Stream must be finite.
-spec fold(datum:monoid(_), _, datum:foldable(_)) -> _.

fold(Fun, Acc, Stream) ->
   foldl(Fun, Acc, Stream).

%%
%% Left-associative fold of a structure
%%
-spec foldl(datum:monoid(_), _, datum:foldable(_)) -> _.

foldl(Fun, Acc, #stream{} = Stream) ->
   foldl(Fun, Fun(head(Stream), Acc), tail(Stream));
foldl(_, Acc, ?None) ->
   Acc.


%%
%% Right-associative fold of a structure
%%
-spec foldr(datum:monoid(_), _, datum:foldable(_)) -> _.

foldr(Fun, Acc, #stream{} = Stream) ->
   lists:foldr(Fun, Acc, stream:list(Stream)).

%% 
%% The fundamental recursive structure constructor, 
%% it applies a function to each previous seed element in turn
%% to determine the next element.
%%
-spec unfold(fun((_) -> _), _) -> datum:foldable(_).

unfold(Fun, Seed)
 when is_function(Fun, 1) ->
   case Fun(Seed) of
      {Head, Next} ->
         new(Head, fun() -> unfold(Fun, Next) end);
      _ ->
         new()
   end.


%%%------------------------------------------------------------------
%%%
%%% stream 
%%%
%%%------------------------------------------------------------------

%%
%% concatenate streams, returns newly-allocated stream composed of elements
%% copied from input streams (in order of input). 
-spec '++'(datum:stream(_), datum:stream(_)) -> datum:stream(_).

'++'(?None, StreamB) ->
   StreamB;
'++'(StreamA, ?None) ->
   StreamA;
'++'(StreamA, StreamB) ->
   new(head(StreamA), fun() -> '++'(tail(StreamA), StreamB) end).

%%
%% concatenate streams, returns newly-allocated stream composed of elements
%% copied from input streams (in order of input). 
-spec '++'([datum:stream(_)]) -> datum:stream(_).

'++'([A,B|T]) ->
   '++'(['++'(A,B)|T]);
'++'([T]) ->
   T.

%%
%% flat stream of streams
-spec flat(datum:stream(_)) -> datum:stream(_).

flat(#stream{head = ?None} = Stream) ->
   flat(tail(Stream));

flat(#stream{head = #stream{} = Head} = Stream) ->
   new(head(Head), fun() -> flat(Stream#stream{head = tail(Head)}) end);

flat(Stream) ->
   Stream.


%%
%% accumulates the partial folds of an input stream into a newly-allocated stream.
%% the output stream is accumulator followed by partial fold.
-spec scan(function(), datum:stream(_)) -> datum:stream(_).
-spec scan(function(), _, datum:stream(_)) -> datum:stream(_).

scan(Fun, #stream{} = Stream) ->
   scan(Fun, head(Stream), tail(Stream)).

scan(Fun, Acc0, #stream{} = Stream) ->
   new(Acc0, fun() -> scan(Fun, Fun(head(Stream), Acc0), tail(Stream)) end);
scan(_, Acc0, ?None) ->
   new(Acc0).


%%
%% takes one or more input streams and returns a newly-allocated stream 
%% in which each element is a list of the corresponding elements of the input 
%% streams. The output stream is as long as the shortest input stream.
-spec zip([datum:stream(_)]) -> datum:stream(_).
-spec zip(datum:stream(_), datum:stream(_)) -> datum:stream(_).

zip(Streams) ->
   case [head(X) || X <- Streams, X =/= ?None] of
      Head when length(Head) =:= length(Streams) ->
         new(Head, fun() -> zip([tail(X) || X <- Streams]) end);
      _ ->
         new()
   end.

zip(A, B) ->
   zip([A, B]).

%%
%% takes one or more input streams and returns a newly-allocated stream,  
%% each element produced by composition function that map list of input heads to
%% new head. The output stream is as long as the longest input stream.
-spec zipwith(function(), [datum:stream(_)]) -> datum:stream(_).
-spec zipwith(function(), datum:stream(_), datum:stream(_)) -> datum:stream(_).

zipwith(_, []) ->
   new();
zipwith(Fun, Streams) ->
   zipwith1(Fun, [head(X) || X <- Streams, X =/= ?None], Streams).

zipwith1(_Fun, [], _Streams) ->
   new();
zipwith1(Fun, Head, Streams) ->
   case Fun(Head) of
      [] ->
         new();
      Hx ->
         new(Hx, fun() -> zipwith(Fun, [tail(X) || X <- Streams, X =/= ?None]) end)
   end.
   
zipwith(Fun, A, B) ->
   zipwith(Fun, [A, B]).


%%%------------------------------------------------------------------
%%%
%%% stream utility
%%%
%%%------------------------------------------------------------------

%%
%% reverse order of elements in stream.
-spec reverse(datum:stream(_)) -> datum:stream(_).

reverse(Stream) ->
   reverse(Stream, new()).

reverse(?None, Acc) ->
   Acc;
reverse(#stream{} = Stream, Acc) ->
   reverse(tail(Stream), new(head(Stream), Acc)).

%%
%% takes list of elements and returns a newly-allocated stream composed of 
%% list elements, repeating them in succession forever.
-spec cycle(list()) -> datum:stream().

cycle(List) -> 
   cycle([], List).

cycle([Head|Tail], List) ->
   new(Head, fun() -> cycle(Tail, List) end);
cycle([], [Head|Tail]=List) ->
   new(Head, fun() -> cycle(Tail, List) end).





%%%------------------------------------------------------------------
%%%
%%% private
%%%
%%%------------------------------------------------------------------
