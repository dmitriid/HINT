-module(hs_engine_mfa).

%%%
%%% Exports
%%%

%%
%% API
%%
-export([ modules_matching/2
	]).

%%%
%%% Import
%%%

-include_lib("eunit/include/eunit.hrl").


%%%
%%% External
%%%

modules_matching(Module, MFAs) ->
	case Module of
		[] -> MFAs;
		_   ->
			ModuleString = atom_to_list(Module),
			ModuleUniversum = atoms_to_utf_set([element(1, X) || X <- MFAs]),
			MM = do_modules_matching(ModuleUniversum, hint_mfa_req:fuzzy_matches(ModuleString)),
			[MFA || {M,_,_}=MFA <- MFAs, lists:member(M, MM)]
	end
.

%%%
%%% Internal
%%%

do_modules_matching(RelevantModules, ModExprs) ->
	ModContains = sets:filter(fun(Element) ->
				case re:run(Element, proplists:get_value(contains, ModExprs), []) of
					nomatch -> false;
					_ -> true
				end
		end, RelevantModules),
	[binary_to_atom(B,latin1)||B<-sets:to_list(ModContains)].


-spec atoms_to_utf_set([atom()]) -> set().
atoms_to_utf_set(Atoms) ->
	sets:from_list([atom_to_binary(Atom, utf8) || Atom <- Atoms]).
