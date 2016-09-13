%% Copyright 2016, Bernard Notarianni
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

-module(barrel_httpc).
-author("Bernard Notarianni").

-export([
         start/2,
         stop/1,
         infos/1,
         put/4,
         put_rev/5,
         get/3,
         delete/4,
         post/3,
         fold_by_id/4,
         changes_since/4,
         revsdiff/3
        ]).

-export([start_link/0]).
-export([stop/0]).

%% gen_server API
-export([init/1, handle_call/3]).
-export([handle_info/2]).
-export([terminate/2]).
-export([code_change/3]).
-export([handle_cast/2]).

start(_Name, _Store) ->
    {error, not_implemented}.

stop(_Name) ->
    {error, not_implemented}.

infos(Barrel) ->
    {200, R} = req(get, Barrel),
    Info = jsx:decode(R, [return_maps]),
    {ok, Info}.

post(Barrel, Doc, _Options) ->
    Req = fun() -> req(post, Barrel, Doc) end,
    post_put(Req).

put(BarrelId, DocId, Doc, _Options) ->
    Sep = <<"/">>,
    Url = <<BarrelId/binary, Sep/binary, DocId/binary>>,
    Req = fun() -> req(put, Url, Doc) end,
    post_put(Req).

post_put(Req) ->
    case Req() of
        {404, _} ->
            {error, not_found};
        {200, R} ->
            Reply = jsx:decode(R, [return_maps, {labels, atom}]),
            DocId = maps:get(id, Reply),
            RevId = maps:get(rev, Reply),
            true = maps:get(ok, Reply),
            {ok, DocId, RevId}
    end.

put_rev(_Db, _DocId, _Body, _History, _Options) ->
    {error, not_implemented}.

get(BarrelId, DocId, _Options) ->
    Sep = <<"/">>,
    Url = <<BarrelId/binary, Sep/binary, DocId/binary>>,
    case req(get, Url) of
        {404, _} ->
            {error, not_found};
        {200, R} ->
            Doc = jsx:decode(R, [return_maps]),
            {ok, Doc}
    end.

delete(BarrelId, DocId, RevId, _Options) ->
    Sep = <<"/">>,
    Rev = <<"?rev=">>,
    Url = <<BarrelId/binary, Sep/binary, DocId/binary, Rev/binary, RevId/binary>>,
    {200, R} = req(delete, Url),
    Reply = jsx:decode(R, [return_maps, {labels, atom}]),
    DocId = maps:get(id, Reply),
    NewRevId = maps:get(rev, Reply),
    true = maps:get(ok, Reply),
    {ok, DocId, NewRevId}.

fold_by_id(_Db, _Fun, _Acc, _Opts) ->
    {error, not_implemented}.

changes_since(BarrelId, Since, Fun, Acc) ->
    ChangesSince = <<"/_changes?feed=longpoll&since=">>,
    SinceBin = integer_to_binary(Since),
    Url = <<BarrelId/binary, ChangesSince/binary, SinceBin/binary>>,
    {200, Reply} = req(get, Url),
    R = jsx:decode(Reply, [return_maps, {labels, atom}]),
    Results = maps:get(results, R),
    Folder = fun(DocInfo, A) ->
                     Seq = maps:get(update_seq, DocInfo),
                     Doc = {error, doc_not_fetched},
                     {ok, FunResult} = Fun(Seq, DocInfo, Doc, A),
                     FunResult
             end,
    lists:foldr(Folder, Acc, Results).

revsdiff(_Db, _DocId, _RevIds) ->
    {error, not_implemented}.

%% ----------
-record(st, {buffer=[]}).

start_link() ->
    case gen_server:start_link({local, ?MODULE}, ?MODULE, [], []) of
        {ok, Pid} -> {ok, Pid};
        {error, {already_started, Pid}} -> {ok, Pid}
    end.

stop() ->
    gen_server:call(?MODULE, stop).

init(_) ->
    {ok, #st{}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State}.

handle_cast(shutdown, State) ->
    {stop, normal, State}.

handle_info(_Info, State) -> {noreply, State}.

%% default gen_server callbacks
terminate(_Reason, _State) ->  ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ----------

req(Method, Url) ->
    req(Method, Url, []).

req(Method, Url, Map) when is_map(Map) ->
    Body = jsx:encode(Map),
    req(Method, Url, Body);

req(Method, Url, Body) ->
    {ok, Code, _Headers, Ref} = hackney:request(Method, Url, [], Body, []),
    {ok, Answer} = hackney:body(Ref),
    {Code, Answer}.
