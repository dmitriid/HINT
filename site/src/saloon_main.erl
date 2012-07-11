-module(saloon_main).

-behaviour(cowboy_http_handler).

-export([init/3, handle/2, terminate/2]).

-include_lib("eunit/include/eunit.hrl").

init({_Any, http}, Req, []) ->
	saloon_init:prepare(Req),
	{ok, Req, 0}.

handle(Req, State) ->
	%?debugFmt(
	%	"erlydtl:compile: ~p~n", 
	%	[
			erlydtl:compile(
				"site/priv/templates/base_landing.dtl", 
				main_dtl, 
				[{out_dir, "site/ebin/"}, {custom_tags_modules, [saloon_lang]}]
			),
	%	]
	%),
	{ok, Rendered} = main_dtl:render([
		{me, [
				{category, <<"">>},
				{controller, <<"saloon_main">>}
			]},
		{categories, []},
		{scripts, []}, 
		{stylesheets, [
			[{name, <<"landing">>}]
		]}
	]),
	{ok, Rep} = cowboy_http_req:reply(
		200, [], Rendered, Req
	),

	{ok, Rep, State+1}.

terminate(_R, _S) ->
	ok.
