
-module(hint_search_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, infinity, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
  NumberOfWorkers = worker_number(),
  Workers = [plt_cache_server],
  ChildSpecs =
               lists:map(fun(Worker) -> pool_spec(Worker, NumberOfWorkers) end, Workers),
  SearchSup = {hint_query_sup, {hint_query_sup, start_link, []}, permanent, infinity, supervisor, [hint_query_sup]},
  WrkSup = ?CHILD(hs_search_api, supervisor),
  {ok, { {one_for_one, 5, 10}, [WrkSup, SearchSup | ChildSpecs]} }.

pool_spec(Worker, Number) ->
  PoolName = list_to_atom("pool_" ++ atom_to_list(Worker)),
  Args = [  {name, {local, PoolName}}
          , {worker_module, Worker}
          , {size, Number}
          , {max_overflow, Number * 2}
         ],
  poolboy:child_spec(PoolName, Args).

worker_number() ->
  case  erlang:system_info(logical_processors_available) of
    unknown ->
      case erlang:system_info(logical_processors_online) of
        unknown ->
          case erlang:system_info(logical_processors) of
            unknown -> 1;
            LP      -> LP
          end;
        LPO     -> LPO
      end;
    LPA     -> LPA
  end.

