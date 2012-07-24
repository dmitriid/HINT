%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_search_api).

-export([start_link/0,
         stop/0,
         reload/0,
         q/1,
         q/2]).

start_link() ->
  hs_search_worker_sup:start_link().

stop() ->
  Wrks = hs_search_worker_sup:all_workers(),
  lists:foreach(fun(W) ->
        try poolboy:stop(W)
        catch
          error:undef -> hs_search_worker:stop(W)
        end
    end, Wrks).

-spec q(hint_search_req:req()) -> {ok, [hs_stage:entry()]}.
q(Req) ->
  q(Req, undefined).

-spec q(hint_search_req:req(), number()|undefined) -> {ok, [hs_stage:entry()]}.
q(Req, Threshold) 
    when is_number(Threshold); 
    Threshold == undefined ->
  F = fun(Wrk) ->
      hs_search_worker:q(Wrk, Req, Threshold)
  end,
  {ok, do_q(F)}.

do_q(F) ->
  Wrks = hs_search_worker_sup:all_workers(),
  ResL = lists:map(
      fun(W) ->
          {ok, R} = try_in_pool(W, F), R
      end, Wrks),
  Cmp = fun(X, Y) -> X >= Y end,
  lists:foldl(fun(L1, L2) ->
        lists:merge(Cmp, L1, L2)
    end, [], ResL).

reload() ->
  lists:foreach(
    fun(W) ->
        hs_search_worker:reload(W)
    end, get_all_workers_from_all_pools()).

get_all_workers_from_all_pools() ->
  Wrks = hs_search_worker_sup:all_workers(),
  try
    lists:concat([workers_from_pool(Pool)
                  || Pool <- Wrks])
  catch
    error:undef -> Wrks
  end.

workers_from_pool(Pool) ->
  Ws = gen_fsm:sync_send_all_state_event(Pool, get_all_workers),
  [Pid || {_Id, Pid, _Type, _Mods} <- Ws].

try_in_pool(Wrk, Fun) ->
  try poolboy:transaction(Wrk, Fun)
  catch _:_ -> Fun(Wrk) end.



