%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_stage_arity).

-behaviour(hs_stage).

-export([apply/2, prepare/3]).

-export_type([state/0]).

-record(state, {
    req_arity = 0 :: non_neg_integer()
    }).

-opaque state() :: #state{}.

apply(#state{ req_arity=Ar }, {_Rank, {_M,_F,Ar}, _Ex} = Entry) 
    when is_integer(Ar) ->
  Entry;
apply(_, _Entry) -> skip.

prepare(_Opts, _PLT, Req) ->
  A = hint_search_req:arity(Req),
  {ok, #state{
      req_arity = A
      }}.

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

mfa_from_req(Req, Bias) ->
  M = hint_search_req:module(Req),
  F = hint_search_req:func(Req),
  A = hint_search_req:arity(Req),
  {M, F, A+Bias}.

test_for_arity_bias(B) ->
  Req = hint_search_req:new("foo:bar(X,Y) -> B"),
  MFA = mfa_from_req(Req, B),
  Entry = hs_stage:empty_entry_for_mfa(MFA),
  {ok, StageState} = prepare([], dialyzer_plt:new(), Req),
  Entry = ?MODULE:apply(StageState, Entry),
  ok.

arity_eq_test_() ->
  ?_assertEqual(ok, test_for_arity_bias(0)).

arity_neq_test_() ->
  ?_assertError({badmatch, skip}, test_for_arity_bias(1)).

-endif.
