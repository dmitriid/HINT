%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_stage_fuzzy).

-behaviour(hs_stage).

-export([apply/2, prepare/3]).

-export_type([state/0]).

-record(state, {
    rex :: re:mp()
    }).

-opaque state() :: #state{}.

apply(#state{ rex=Re }, {Rank, {M,F,_A}=MFA, Ex}=Entry) ->
  Haystack = mf_to_bins(M,F),
  case re:run(Haystack, Re) of
    {match, MList} ->
      Delta1 = length(MList)/size(Haystack),
      Delta2 = 1/(gaps_cost([I || {I,1} <- MList])),
      {Rank+Delta1+Delta2, MFA, Ex};
    nomatch -> 
      Entry
  end.

prepare(_Opts, _PLT, Req) ->
  M = hint_search_req:module(Req),
  F = hint_search_req:func(Req),
  S = mf_to_bins(M, F),
  R = str_to_rex(S),
  {ok, C} = compile(R),
  {ok, #state{
      rex = C
      }}.

gaps_cost([]) -> 1;
gaps_cost([_]) -> 1;
gaps_cost([X1, X2 | R]) ->
  (X2-X1) + gaps_cost(R).

mf_to_bins(M, F) ->
  iolist_to_binary([to_l(M), " ", to_l(F)]).

str_to_rex(S) ->
  S1 = unicode:characters_to_list(S),
  S2 = re:split(S1, "\\s", [{return, list}]),
  R1 = [[quote(Ch) || Ch <- Si] || Si <- S2],
  R2 = string:join(R1, " ?"),
  iolist_to_binary([R2, "$"]).

quote(L) ->
  ["(", L, ").*"].

compile(RexStr) ->
  re:compile(RexStr, [unicode]).

to_l(L) when is_list(L) -> L;
to_l(L) when is_atom(L) ->
  atom_to_list(L);
to_l(L) when is_integer(L) ->
  integer_to_list(L);
to_l(L) when is_binary(L) ->
  binary_to_list(L).
