%%%-------------------------------------------------------------------
%%% @author Meleshkin Valery
%%% @copyright 2012 HINT Spawnfest Team
%%%-------------------------------------------------------------------

-module(hs_stage_types).

-behaviour(hs_stage).

-export([apply/2, prepare/3]).
-export([test_ranks/2]).

-export_type([state/0]).

-record(state, {
    plt = dialyzer_plt:new() :: dialyzer_plt:plt(),
    req = undefined :: {erl_types:erl_type(), 
                        [erl_types:erl_type()]}
    }).

-opaque state() :: #state{}.

-spec apply(state(), hs_stage:entry()) -> hs_stage:entry().
apply(#state{plt=PLT, req=RTS}, {PrevRank, MFA, Extra}) ->
  case dialyzer_plt:lookup(PLT, MFA) of
    none -> PrevRank;
    {value, {FTR, FTA}} -> 
      TypeString = erl_types:t_to_string(erl_types:t_fun(FTA,FTR)),
      {(PrevRank+fun_rank(RTS, {FTR, FTA})), MFA,
       [{type_string, TypeString}|Extra]}
  end.

-spec prepare(proplists:proplist(), dialyzer_plt:plt(), 
              hint_search_req:req()) -> {ok, state()}.
prepare(_Opts, PLT, Req) ->
  {ok, R} = compile_request_to_sig(PLT, Req),
  {ok, #state{
      plt = PLT,
      req = R
      }}.

%% For testing purposes only
test_ranks(PLT, String) ->
  Req = hint_search_req:new(String),
  {ok, S} = prepare([], PLT, Req),
  Modules = sets:to_list(dialyzer_plt:all_modules(PLT)),
  Fun = fun(Mod) ->
      {value, Sigs} = dialyzer_plt:lookup_module(PLT, Mod),
      [?MODULE:apply(S, {1, MFA, []}) ||
        {{_,_,A}=MFA, _, _} <- Sigs,
        A =:= hint_search_req:arity(Req)]
  end,
  lists:reverse(lists:keysort(2,lists:flatmap(Fun,Modules))).

compile_request_to_sig(PLT, Req) ->
  Mod = list_to_atom(temp_mod_name()),
  F = Mod,
  A = hint_search_req:arity(Req),
  {ok, AbstractCode} = abstract_code_for_req(Req),
  {ok, Contract} = cotract_for_func_code(PLT, {Mod, F, A}, AbstractCode),
  {ok, {dialyzer_contracts:get_contract_return(Contract),
        dialyzer_contracts:get_contract_args(Contract)}}.

%% Gen magic-file and extracts abstract code
abstract_code_for_req(Req) ->
  File = temp_file(),
  Data = temp_file_contents(Req),
  ok = file:write_file(File, Data),
  {ok, AbstractCode} = epp:parse_file(File, [], []),
  rm_temp_file(File),
  {ok, AbstractCode}.

temp_file_contents(Req) ->
  S = hint_search_req:string(Req),
  ["-module('",temp_mod_name(),"').\n"
   "-spec '", temp_mod_name(), "'", S, "."].

cotract_for_func_code(PLT, {Mod,_,_}=MFA, AbstractCode) ->
  CS0 = dialyzer_codeserver:new(),
  CS1 = push_code_into_codeserver(CS0, Mod, AbstractCode),
  CS2 = process_remote_types(CS1, PLT), 
  {ok, {_, Contract}} = dialyzer_codeserver:lookup_mfa_contract(MFA, CS2),
  dialyzer_codeserver:delete(CS2),
  {ok, Contract}.

push_code_into_codeserver(CS, Mod, AbstractCode) ->
  {ok, RecDict} = dialyzer_utils:get_record_and_type_info(AbstractCode),
  {ok, SpecDict, CbDict} = dialyzer_utils:get_spec_info(Mod, AbstractCode, RecDict),
  CS1 = dialyzer_codeserver:store_temp_records(Mod, RecDict, CS),
  dialyzer_codeserver:store_temp_contracts(Mod, SpecDict, CbDict, CS1).

process_remote_types(CodeServer1, PLT) ->
  NewRecords = dialyzer_codeserver:get_temp_records(CodeServer1),
  OldRecords = dialyzer_plt:get_types(PLT), 
  OldExTypes = dialyzer_plt:get_exported_types(PLT),
  MergedRecords = dialyzer_utils:merge_records(NewRecords, OldRecords),
  CodeServer2 = dialyzer_codeserver:set_temp_records(MergedRecords, CodeServer1),
  CodeServer3 = dialyzer_codeserver:insert_temp_exported_types(OldExTypes, CodeServer2),
  CodeServer4 = dialyzer_utils:process_record_remote_types(CodeServer3),
  dialyzer_contracts:process_contract_remote_types(CodeServer4).

fun_rank({Res, Args}=_ReqResArgs, CandidateResArgs) ->
  CRAList  = ts_to_list(CandidateResArgs),
  RotsRank = fun(ArgsRotation) ->
      ARanks = lists:zipwith(fun types_rank/2, 
                             [Res|ArgsRotation], CRAList),
      lists:sum(ARanks) / length(ARanks) 
  end,
  lists:max(lists:map(RotsRank, rotations(Args))).

ts_to_list({Ret, L}) -> 
  [Ret | L].

types_rank(T1, T2) ->
  try {erl_types:t_to_tlist(T1), 
       erl_types:t_to_tlist(T2)} of
    %% T2 is a product while T1 is not.
    {[_T],TL} ->
      lists:max([rank_(T1, T2i) || T2i <- TL]);
    _  -> 
      rank_(T1, T2)
  catch
    _:_ -> 
      rank_(T1, T2)
  end.

rank_(T1, T2) ->
  Eql = erl_types:t_is_equal(T1, T2),
  Ins = erl_types:t_is_instance(T1, T2),
  Sub = erl_types:t_is_subtype(T1, T2),
  Sup = erl_types:t_is_subtype(T2, T1),
  Any = (T2 == erl_types:t_any()),
  if
    Eql  -> 0.9;
    Sup  -> 0;
    Sub  -> 
      if
        Any  -> -0.1;
        true ->  0.2
      end;
    Ins  -> 0.3;
    true -> -0.5
  end.

rotate([H|L]) ->
  L ++ [H].

rotations(L) ->
  tl(lists:foldl(
      fun(_,R) ->
          [rotate(hd(R))|R]
      end, [L], L)).

temp_mod_name() -> 
  atom_to_list(?MODULE) ++ "_temp_mod".

temp_file() ->
  Ext = ".erl",
  Dir = mochitemp:mkdtemp(),
  filename:join(Dir, temp_mod_name() ++ Ext).

rm_temp_file(File) ->
  mochitemp:rmtempdir(filename:dirname(File)).
