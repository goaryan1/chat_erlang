-module(client).
-export([start/0, send_message/0, loop/1, exit/0, start_helper/0]).
-record(client_status, {name, serverSocket, startPid, spawnedPid}).

start() ->
    ClientStatus = #client_status{startPid = self()},
    SpawnedPid = spawn(client, start_helper, [ClientStatus]),
    put(spawnedPid, SpawnedPid),
    put(localPid, self()).

start_helper() ->
    {ok, Socket} = gen_tcp:connect('localhost', 9991, [binary, {active, true}]),
    gen_tcp:recv(Socket, 0),
    receive
        {tcp, Socket, BinaryData} ->
            Data = erlang:binary_to_term(BinaryData),
            {connected, Name} = Data,
            io:format("connected to server, with username ~p~n", [Name]),
            ClientStatus = #client_status{serverSocket = Socket, name = Name},
            loop(ClientStatus);
        {tcp_closed, Socket} ->
            io:format("not connected to the server: ~n")
    end.

loop(ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    StartPid = ClientStatus#client_status.startPid,
    gen_tcp:recv(Socket, 0),    % activate listening
    receive
        {tcp, Socket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            case Data of
                {message, Message} ->
                    io:format("Received: ~s~n", [Message]),
                    loop(Socket);
                true ->
                    io:format("Undefined message received~n")
            end;
        {tcp_closed, Socket} ->
            io:format("Connection closed~n"),
            ok;
        {StartPid, {message, Message, Receiver}} ->
            BinaryData = term_to_binary({message, Message, Receiver}),
            gen_tcp:send(Socket, BinaryData);
        {StartPid, {message, Message}} ->
            BinaryData = term_to_binary({message, Message}),
            gen_tcp:send(Socket, BinaryData);
        {StartPid, {exit}} ->
            BinaryData = term_to_binary({exit}),
            gen_tcp:send(Socket, BinaryData)
    end,
    loop(ClientStatus).
    
send_message() ->
    Message = io:get_line("Enter message (or 'exit' to quit): "),
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {message, Message}}.

exit() ->
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {exit}}.

% help() ->
%     % show available commands
%     io:format()
