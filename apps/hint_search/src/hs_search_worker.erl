%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_search_worker).
-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/1,
         start_link/2,
         stop/1,
         reload/1,
         q/2,
         q/3]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-type stage_desc() :: {module(), proplists:proplist(), term()}.
-record(state, {
    stages  = [] :: [stage_desc()],
    plt_src = dialyzer_plt:get_default_plt() 
              :: file:filename() 
              | {priv, file:filename()} 
              | {module(), atom(), list()},
    plt     = undefined :: dialyzer_plt:plt() | undefined
    }).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(PLTSrc, Stages) ->
  start_link(?MODULE, [{stages, Stages},
                       {plt_src, PLTSrc}]).

start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

stop(Wrk) ->
  gen_server:call(Wrk, stop).

-spec q(pid()|atom(), hint_search_req:req()) ->
  {ok, [hs_stage:entry()]}.
q(Wrk, Req) ->
  q(Wrk, Req, undefined).

-spec q(pid()|atom(), hint_search_req:req(), 
        number() | undefined) ->
  {ok, [hs_stage:entry()]}.
q(Wrk, Req, Threshold) 
    when is_number(Threshold); 
    Threshold == undefined ->
  gen_server:call(Wrk, {q, Req, Threshold}).

reload(Wrk) ->
  Wrk ! load_plt.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(Args) ->
  RawStages = proplists:get_value(stages, Args, fail_on_this),
  Stages = uniform_stages(RawStages),
  DefSrc = dialyzer_plt:get_default_plt(),
  PLTSrc = proplists:get_value(plt_src, Args, DefSrc),
  reload(self()),
  %% meta only!
  put('**plt_src**', PLTSrc),
  put('**stages**', Stages),
  {ok, #state{
      stages  = Stages,
      plt_src = PLTSrc
      }}.

handle_call(stop, _From, State) ->
  {stop, normal, ok, State};

handle_call({q, Req, Threshold}, _From, State) ->
  StateTemp = prepare_for_req(State, Req),
  R = process(StateTemp),
  {reply, {ok, cut(R, Threshold)}, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(load_plt, #state{ plt_src = {M,F,A} } = State) ->
  PLT = apply(M, F, A),
  {noreply, State#state{ plt=PLT }};
handle_info(load_plt, #state{ plt_src = Path } = State) ->
  PLT = dialyzer_plt:from_file(plt_path(Path)),
  {noreply, State#state{ plt=PLT }};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

-spec uniform_stages([atom() | tuple(2) | tuple(3)]) -> [stage_desc()].
uniform_stages(Stages) ->
  UF = fun
    ({S, O})             -> {S, O, undefined};
    (S) when is_atom(S)  -> {S, [], undefined};
    (T) when is_tuple(T) -> T
  end,
  lists:map(UF, Stages).

entry_from_sig({MFA, _Ret, _Args}) ->
  hs_stage:empty_entry_for_mfa(MFA).

process(#state{ plt=PLT } = State) ->
  Modules = sets:to_list(dialyzer_plt:all_modules(PLT)),
  Fun = fun(Mod) ->
      {value, Sigs} = dialyzer_plt:lookup_module(PLT, Mod),
      process_entries(State, Sigs)
  end,
  lists:reverse(lists:sort(lists:flatmap(Fun, Modules))).

process_entries(State, Entries) ->
  lists:foldl(fun(Entry, Res) ->
        case process_entry_sig(State, Entry) of
          % When Entry is 'ignore', 'skip', etc.
          Ent when is_atom(Ent) ->
            Res;
          Ent when is_tuple(Ent) ->
            [Ent|Res]
        end
    end, [], Entries).

process_entry_sig(#state{ stages=SL }, Sig) ->
  Entry = entry_from_sig(Sig),
  lists:foldl(fun apply_stage/2, Entry, SL).

-spec apply_stage(stage_desc(), hs_stage:entry()) -> hs_stage:entry().
apply_stage(_Stage, Entry) when is_atom(Entry) ->
  % When Entry is 'ignore', 'skip', etc.
  Entry;
apply_stage({undefined, _Opt, undefined}, Entry) ->
  Entry;
apply_stage({Mod, _Opt, State}, Entry) ->
  try Mod:apply(State, Entry)
  catch
    _:Reason ->
      error_logger:warning_msg(
        "Stage ~p failed to process entry ~p. Reason: ~p",
        [Mod, Entry, Reason]),
      Entry
  end.

prepare_for_req(#state{ stages=SL, plt=PLT } = State, Req) ->
  NewSL = lists:map(fun(StageDesc) ->
        prepare_stage(StageDesc, PLT, Req)
    end, SL),
  State#state{ stages=NewSL }.

-spec prepare_stage(stage_desc(), dialyzer_plt:plt(),
                    hint_search_req:req()) -> stage_desc().
prepare_stage({Mod, Opt, _OldState}, PLT, Req) ->
  try
    {ok, NewState} = Mod:prepare(Opt, PLT, Req),
    {Mod, Opt, NewState}
  catch
    _:Reason ->
      error_logger:warning_msg(
        "Stage ~p failed to prepare for request ~p. Reason: ~p",
        [Mod, Req, {Reason, erlang:get_stacktrace()}]),
      {undefined, [], undefined}
  end.

cut(L, undefined) -> L;
cut(L, Threshold) ->
  lists:takewhile(fun({W,_,_})-> W >= Threshold end, L).

plt_path({priv, Path}) ->
  case application:get_application() of
    {ok, App} ->
      filename:join(code:priv_dir(App), Path);
    undefined ->
      Path
  end;
plt_path(Path) -> Path.

%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

request() ->
  "foo:bar([A], fun((A)->B)) -> [B]".

stages() ->
  [hs_stage_arity, {hs_stage_types, []}].

setup_default() ->
  %% TODO don't use default PLT for this test
  {ok, Wrk} = start_link([{stages, stages()}]),
  Wrk.

setup_mfa() ->
  PltGen = {hs_biftab_plt, tabs_to_plt, [["../priv"]]},
  {ok, Wrk} = start_link([{stages, stages()},
                          {plt_src, PltGen}]),
  Wrk.

cleanup(Wrk) ->
  stop(Wrk).

get_first(0, _)  -> [];
get_first(_, []) -> [];
get_first(N, [E | List]) ->
  [E | get_first(N-1, List)].

do_search(Wrk, Threshold) ->
  Req = hint_search_req:new(request()),
  {ok, Res} = q(Wrk, Req, Threshold),
  ?debugFmt("~nTop results: ~p~n", [get_first(5, Res)]),
  Res.

is_valid_search_reuslt([]) -> true;
is_valid_search_reuslt([{Score1, MFA, _Ex},
                        {Score2, _,     _} | Rest])
    when (Score1 >= Score2) and (tuple_size(MFA) == 3) ->
  is_valid_search_reuslt(Rest);
is_valid_search_reuslt([{_Score, MFA, _Ex} | Rest])
    when (tuple_size(MFA) == 3) ->
  is_valid_search_reuslt(Rest);
is_valid_search_reuslt(_) -> false.

smth_found_and_well_formated(Wrk) ->
  Thres   = 0.2,
  Unbound = do_search(Wrk, undefined),
  Bound   = do_search(Wrk, Thres),
  CheckTh = fun({W,_,_}) -> W >= Thres end,
  [?_assert(is_valid_search_reuslt(Unbound)),
   ?_assert(is_valid_search_reuslt(Bound)),
   ?_assert(lists:all(CheckTh, Bound)),
   ?_assert(is_sublist(Bound, Unbound))].

is_sublist([X|_]=Sub, List) ->
  Rest = lists:dropwhile(fun(Y) -> Y =/= X end, List),
  lists:prefix(Sub, Rest).

well_formatted_result_test_() ->
  {"Search result for defult PLT is a descending oredered list",
   {setup,
    fun setup_default/0, fun cleanup/1,
    fun smth_found_and_well_formated/1}}.

mfa_plt_gen_test_() ->
  {"Search result for generated PLT (from bif.tab) is a descending oredered list",
   {setup,
    fun setup_mfa/0, fun cleanup/1,
    fun smth_found_and_well_formated/1}}.

-endif.

