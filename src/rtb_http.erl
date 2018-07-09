%%%-------------------------------------------------------------------
%%% @author Evgeny Khramtsov <ekhramtsov@process-one.net>
%%% @copyright (C) 2002-2018 ProcessOne, SARL. All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%%-------------------------------------------------------------------
-module(rtb_http).
-compile([{parse_transform, lager_transform}]).

%% API
-export([start_link/0, docroot/0, do/1]).

-include_lib("inets/include/httpd.hrl").

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    Opts = httpd_options(),
    DocRoot = proplists:get_value(document_root, Opts),
    case create_index_html(DocRoot) of
	ok ->
	    case inets:start(httpd, Opts) of
		{ok, Pid} ->
		    lager:info("Accepting HTTP connections on port ~B",
			       [proplists:get_value(port, Opts)]),
		    {ok, Pid};
		Err ->
		    Err
	    end;
	{error, _} = Err ->
	    Err
    end.

docroot() ->
    ServerRoot = rtb_config:get_option(www_dir),
    filename:join(ServerRoot, "data").

do(#mod{method = Method, data = Data}) ->
    if Method == "GET"; Method == "HEAD" ->
	    case lists:keyfind(real_name, 1, Data) of
		{real_name, {Path, _}} ->
		    Field = filename:basename(Path, ".png"),
		    Mod = rtb_config:get_option(module),
		    try lists:keymember(
			  list_to_existing_atom(Field), 1, Mod:stats()) of
			true ->
			    rtb_plot:render(Field);
			false ->
			    ok
		    catch _:_ ->
			    ok
		    end;
		false ->
		    ok
	    end;
       true ->
	    ok
    end,
    {proceed, Data}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
httpd_options() ->
    ServerRoot = rtb_config:get_option(www_dir),
    Port = rtb_config:get_option(www_port),
    {_, Domain, _} = rtb_config:get_option(jid),
    DocRoot = filename:join(ServerRoot, "data"),
    [{port, Port},
     {server_root, ServerRoot},
     {document_root, DocRoot},
     {mime_types, [{"html", "text/html"},
		   {"png", "image/png"}]},
     {directory_index, ["index.html"]},
     {modules, [mod_alias, ?MODULE, mod_get, mod_head]},
     {server_name, binary_to_list(Domain)}].

create_index_html(DocRoot) ->
    Mod = rtb_config:get_option(module),
    Data = ["<!DOCTYPE html><html><body>",
	    lists:map(
	      fun({F, _}) ->
		      ["<img src='/", atom_to_list(F), ".png'>"]
	      end, Mod:stats()),
	    "</body></html>"],
    File = filename:join(DocRoot, "index.html"),
    case filelib:ensure_dir(File) of
	ok ->
	    case file:write_file(File, Data) of
		ok ->
		    ok;
		{error, Why} = Err ->
		    lager:critical("Failed to write to ~s: ~s",
				   [File, file:format_error(Why)]),
		    Err
	    end;
	{error, Why} = Err ->
	    lager:critical("Failed to create directory ~s: ~s",
			   [DocRoot, file:format_error(Why)]),
	    Err
    end.
