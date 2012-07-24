%% Interface to all the weird stuff

-module(hint_search).

-export([ start/0
        , stop/0
        , q/1
        , q/2]).
	
start() ->
	application:start(hint_search).

stop() ->
	application:stop(hint_search).

q(Query) ->
	hint_query_worker:q(Query).

q(Query, Thres) ->
	hint_query_worker:q(Query, Thres).
