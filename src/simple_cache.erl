-module(simple_cache).
-behaviour(gen_server).
-define(SERVER, ?MODULE).
%% Expiration is in seconds, erlang:send_after/3 uses milliseconds.
-define(EXPIRATION_UNIT, 1000).
-record(state, {table}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([start_link/0, insert/2, insert/3, lookup/1, lookup/2, delete/1]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

insert(Key, Value) ->
    gen_server:cast(?SERVER,{insert, Key, Value, infinity}).

insert(Key, _Value, 0) -> 
    delete(Key);

insert(Key, Value, Expires) when is_number(Expires), Expires > 0 ->
    gen_server:cast(?SERVER, {insert, Key, Value, Expires}).

lookup(Key) -> 
    get_key(?SERVER, Key).

lookup(Key, Default) ->
    case lookup(Key) of
        {ok, Value} ->
            Value;
        {error, missing} ->
            Default
    end.

delete(Key) ->
    gen_server:cast(?SERVER, {delete, Key}),
    ok.

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
init(_Args) ->
    EtsTable = ets:new(?SERVER, [{read_concurrency, true}, named_table]),
    {ok, #state{table = EtsTable}}.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

% Inserts a key without an expiration.
handle_cast({insert, Key, Value, infinity}, #state{table=Table} = State) ->
    ets:insert(Table, {Key, Value}),
    {noreply, State};
% Inserts a key with an expiration.
handle_cast({insert, Key, Value, ExpireTime}, #state{table=Table} = State) ->
    ets:insert(Table, {Key, Value}),
    erlang:send_after(?EXPIRATION_UNIT * ExpireTime, ?SERVER, {expired, Key}),
    {noreply, State};
% Delete a key from the cache.
handle_cast({delete, Key}, #state{table=Table}=State) ->
    ets:delete(Table, Key),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

% We've timed out, so a key has in all likelihood expired.
handle_info({expired, Key}, #state{table=Table}=State) ->
    ets:delete(Table, Key),    
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{table=Table}) ->
    catch ets:delete(Table),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

% Retrieves an item from the cache.
get_key(Table, Key) ->
     case ets:lookup(Table, Key) of
        [{Key, Value}] ->
            {ok, Value};
        [] ->
            {error, missing}
    end.

