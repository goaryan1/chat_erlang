-module(client).
-export([start/0, send_message/0, loop/1]).
-record(client_status, {name, serverSocket}).

start() ->
    {ok, Socket} = gen_tcp:connect('localhost', 9991, [binary, {active, true}]),
    gen_tcp:recv(Socket, 0),
    receive
        {tcp, Socket, BinaryData} ->
            Data = erlang:binary_to_term(BinaryData),
            {connected, Name} = Data,
            io:format("connected to server, with username ~p~n", [Name]);
        {tcp_closed, Socket} ->
            io:format("not connected to the server: ~n")
    end,
    ClientStatus = #client_status{serverSocket = Socket},
    % put(startPid, self()),
    SpawnedPid = spawn(client, loop,[ClientStatus]).
    % put(spawnedPid, SpawnedPid).

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
