%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_stage).

-export([empty_entry_for_mfa/1]).
-export_type([entry/0]).

-type entry() :: {number(), mfa(), proplists:proplist()}.

-callback apply(State::term(), entry()) -> entry() | skip | ignore.
-callback prepare(proplists:proplist(), dialyzer_plt:plt(), 
                  hint_search_req:req()) -> 
  {ok, State::term()} |
  {error, Reason::term}.

empty_entry_for_mfa(MFA) ->
  {0, MFA, []}.


