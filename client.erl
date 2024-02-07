-module(client).
-export([start/0, send_message/0, loop/1]).
-record(client_status, {name, serverSocket}).

start() ->
    {ok, Socket} = gen_tcp:connect('localhost', 9991, [binary, {active, true}]),
    case gen_tcp:recv(Socket, 0) of
        {ok, BinaryData} ->
            ListData = erlang:binary_to_list(BinaryData),
            {connected, Name} = lists:nth(1, ListData),
            io:format("connected to server, with username ~p~n", [Name]);
        {error, Reason} ->
            io:format("not connected to the server: ~p~n", [Reason])
    end,
    ClientStatus = #client_status{serverSocket = Socket},
    put(startPid, self()),
    SpawnedPid = spawn(client, loop,[ClientStatus]),
    put(spawnedPid, SpawnedPid).

loop(ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    gen_tcp:recv(Socket, 0),    % activate listening
    receive
        {tcp, Socket, {Message}} ->
            io:format("Received: ~s~n", [Message]),
            loop(Socket);
        {tcp_closed, Socket} ->
            io:format("Connection closed~n"),
            ok;
        true ->
            io:format("Receive message function called~n")
    end,
    loop(ClientStatus).
    
send_message() ->
    Message = io:get_line("Enter message (or 'exit' to quit): "),
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {message, Message}}.
