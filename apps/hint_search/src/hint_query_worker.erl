-module(hint_query_worker).
-behaviour(gen_server).

-export([q/1, q/2]).

%%
%% gen_server callbacks
%%
-export([ start_link/0
        , init/1
        , code_change/3
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        ]).

q(Request) -> q(Request, undefined).

q(Request, Threshold) 
    when is_number(Threshold);
    Threshold == undefined ->
  {ok, Pid} = supervisor:start_child(hint_query_sup, []),
  gen_server:call(Pid, {q, Request, Threshold}, infinity).

start_link() ->
  gen_server:start_link(?MODULE, [], []).

%%
%% gen_server callbacks
%%

init(_Args) ->
    {ok, []}.

handle_call({q, Req, Threshold}, _From, State) ->
  R = try 
    hs_search_api:q(hint_search_req:new(Req), Threshold)
  catch 
    _:Reason -> {error, Reason}
  end,
  {stop, normal, R, State}.

handle_cast(_, State) ->
  {noreply, State}.

handle_info(_, State) ->
  {noreply, State}.

code_change(_, State, _) ->
  {ok, State}.

terminate(_Reason, _State) ->
  ok.
