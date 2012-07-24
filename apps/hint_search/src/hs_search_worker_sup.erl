%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_search_worker_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, all_workers/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILDW(I, Opts), {I, {I, start_link, Opts}, permanent, 1000, worker, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

all_workers() ->
  C = supervisor:which_children(?MODULE),
  [Pid || {_Id, Pid, _Type, _Mods} <- C].

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
  {ok, {{one_for_one, 5, 10}, workers_spec()}}.

workers_spec() ->
  try workers_spec(fun pool_spec/3)
  catch error:undef -> workers_spec(fun plain_spec/3) end.

workers_spec(Func) ->
  [Func(Id, hs_search_worker, Opts)
     || {Id, Opts} <- get_workers_conf()].

get_workers_conf() ->
  BaseStages = get_base_stages(),
  case application:get_env(workers) of
    {ok, Wrks} ->
      [{Id, prepend_stages(BaseStages, Opts)} 
       || {Id, Opts} <- Wrks];
    undefined ->
      [{default, prepend_stages(BaseStages, [])}]
  end.

get_base_stages() ->
  case application:get_env(base_stages) of
    {ok, BS}  -> BS;
    undefined -> []
  end.

prepend_stages(Stages, Opts) ->
  Key = stages,
  OldStages = proplists:get_value(Key, Opts, []),
  NewStages = Stages ++ OldStages,
  lists:keystore(Key, 1, Opts, {Key, NewStages}).

plain_spec(Id, Worker, Opts) -> 
  {Id, 
   {Worker, start_link, [Opts]}, 
   temporary, 5000, worker, [Worker]}.

pool_spec(Id, Worker, Opts) ->
  Number = workers_number(),
  Args = [{worker_module, Worker}, 
          {size, Number}, 
          {max_overflow, Number * 2}] ++ Opts,
  poolboy:child_spec(Id, Args).

workers_number() ->
  case erlang:system_info(logical_processors_available) of
    unknown ->
      case erlang:system_info(logical_processors_online) of
        unknown -> 
          case erlang:system_info(logical_processors) of
            LP when is_integer(LP), LP > 1 -> LP; % dialyzer bug?
            _Unknown -> 1
          end;
        LPO     -> LPO
      end;
    LPA    -> LPA
  end.

