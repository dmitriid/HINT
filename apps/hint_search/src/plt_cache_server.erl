-module(plt_cache_server).
-behaviour(gen_server).
-behaviour(poolboy_worker).

%%%
%%% Exports
%%%

%%
%% API
%%

-export([ start_link/1
        , load/1
        , update/0
        , apply/1
        , lookup/2
        ]).

%%
%% gen_server callbacks
%%
-export([ init/1
        , code_change/3
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        ]).

%%%
%%% Defines
%%%

-define(POOL, pool_plt_cache_server).
-record(state, {plt, ets, file}).

%%%
%%% Import
%%%

-include_lib("dialyzer/src/dialyzer.hrl").
-include_lib("eunit/include/eunit.hrl").

%%%
%%% API
%%%

-spec start_link([{file, Path::string()}] | []) -> ok.
start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

%%
%% Load a specified Plt file. 
%%
-spec load(Path::string()) -> ok.
load(File) ->
  Worker = poolboy:checkout(?POOL),
  Res = gen_server:call(Worker, {load, File}, infinity),
  poolboy:checkin(?POOL, Worker),
  Res.

%%
%% Update all info from the currently loaded file
%%
-spec update() -> ok.
update() ->
  Worker = poolboy:checkout(?POOL),
  Res = gen_server:call(Worker, update, infinity),
  poolboy:checkin(?POOL, Worker),
  Res.

%%
%% Apply a specified function. Plt will be prepended to the list of arguments
%%
-spec apply({Module::atom(), Func::atom(), Args::list()}) -> any().
apply(MFA) ->
  Worker = poolboy:checkout(?POOL),
  Res = gen_server:call(Worker, {apply, MFA}, infinity),
  poolboy:checkin(?POOL, Worker),
  Res.

%%
%% Lookup arity
%%
-spec lookup(atom(), byte()) -> any().
lookup(Module, Arity) ->
  Worker = poolboy:checkout(?POOL),
  Res = gen_server:call(Worker, {lookup, {Module, Arity}}, infinity),
  poolboy:checkin(?POOL, Worker),
  Res.

%%%
%%% Callbacks
%%%

init(Args) ->
  File = get_file(Args),
  Plt = dialyzer_plt:from_file(File),
  Ets = create_and_update_ets(Plt),
  {ok, #state{plt = Plt, ets = Ets, file = File}}.

handle_call({load, File}, _From, #state{ets=Ets} = State) ->
  Plt  = dialyzer_plt:from_file(File),
  clean_update(Ets, Plt),
  {reply, ok, State#state{plt=Plt, file=File}, hibernate};

handle_call(update, _From, #state{ets=Ets, file=File} = State) ->
  Plt  = dialyzer_plt:from_file(File),
  clean_update(Ets, Plt),
  {reply, ok, State, hibernate};

handle_call({lookup, {Module, Arity}}, _From, #state{ets=Ets} = State) ->
  MFA = ets:lookup(Ets, Arity),
  Matched = hs_engine_mfa:modules_matching(Module, MFA),
  {reply, Matched, State};

handle_call({apply, {M, F, A}}, _From, #state{plt=Plt} = State) ->
  R = (catch erlang:apply(M, F, [Plt | A])),
  {reply, R, State, hibernate}.

handle_cast(_, State) ->
  {noreply, State}.

handle_info(_, State) ->
  {noreply, State}.

code_change(_, State, _) ->
  {ok, State}.

terminate(shutdown, #state{ets=Ets}) ->
  ets:delete(Ets),
  ok.

%%%
%%% Internal
%%%

get_file(Args) ->
  File = proplists:get_value(file, Args, undefined),
  case File of
    undefined -> 
      case application:get_env(plt_path) of
        undefined              -> dialyzer_plt:get_default_plt();
        {ok, {priv_dir, PrivFile}} ->
            {ok, AppName} = application:get_application(),
            PrivDir = filename:absname(code:priv_dir(AppName)),
            filename:absname_join(PrivDir, PrivFile);
        {ok, PltPath}    -> filename:absname(PltPath)
      end;
    Path      -> filename:absname(Path)
  end.

create_and_update_ets(Plt) ->
  Ets = ets:new(?MODULE, [ bag
                         , private
                         , {keypos, 3}
                         , {write_concurrency,true}
                         , {read_concurrency,true}]),
  update_ets(Ets, Plt),
  Ets.

clean_update(Ets, Plt) ->
  ets:delete_all_objects(Ets),
  update_ets(Ets, Plt).

update_ets(Ets0, Plt) ->
  AllModulesSet = dialyzer_plt:all_modules(Plt),
  AllModules = sets:to_list(AllModulesSet),
	% wrong heuristic :)
  Modules = [M || M <- AllModules,
			string:equal(atom_to_list(M),
				string:to_lower(atom_to_list(M)))],
  MFAList = get_mfas(Modules, Plt),
  ets:insert(Ets0, MFAList),
  ok.

get_mfas(Modules, Plt) -> get_mfas(Modules, Plt, []).

get_mfas([], _, Acc)     ->
  Acc;
get_mfas([H|T], Plt, Acc0) ->
  {value, MFATypes} = dialyzer_plt:lookup_module(Plt,H),
  Acc1 = mfa_from_types(MFATypes, Acc0),
  get_mfas(T, Plt, Acc1).

mfa_from_types([], Acc)                -> Acc;
mfa_from_types([{MFA, _, _} | T], Acc) -> mfa_from_types(T, [MFA | Acc]).

