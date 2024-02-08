-module(client).
-export([start/0, send_message/0, loop/1, exit/0, start_helper/1, send_private_message/0, show_clients/0, help/0, set_name/0]).
-record(client_status, {name, serverSocket, startPid, spawnedPid}).

start() ->
    ClientStatus = #client_status{startPid = self()},
    SpawnedPid = spawn(client, start_helper, [ClientStatus]),
    put(spawnedPid, SpawnedPid),
    put(startPid, self()).

start_helper(ClientStatus) ->
    {ok, Socket} = gen_tcp:connect('localhost', 9991, [binary, {active, true}]),
    gen_tcp:recv(Socket, 0),
    io:format("1. ~p~n", [Socket]),
    receive
        {tcp, Socket, BinaryData} ->
            io:format("2. ~p~n", [Socket]),
            Data = erlang:binary_to_term(BinaryData),
            {connected, Name} = Data,
            io:format("connected to server, with username ~p~n", [Name]),
            ClientStatus1 = ClientStatus#client_status{serverSocket = Socket, name = Name},
            loop(ClientStatus1);
        {tcp_closed, Socket} ->
            io:format("not connected to the server: ~n")
    end.

loop(ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    StartPid = ClientStatus#client_status.startPid,
    % io:format("StartPid = ~p~n", [StartPid]),
    gen_tcp:recv(Socket, 0),    % activate listening
    receive
        {tcp, Socket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            case Data of
                {message, SenderName, Message} ->
                    io:format("Received: ~p from user ~p~n", [Message, SenderName]),
                    loop(ClientStatus);
                true ->
                    io:format("Undefined message received~n")
            end;
        {tcp_closed, Socket} ->
            io:format("Connection closed~n"),
            ok;
        {StartPid, {private_message, Message, Receiver}} ->
            BinaryData = term_to_binary({private_message, Message, Receiver}),
            gen_tcp:send(Socket, BinaryData);
        {StartPid, {message, Message}} ->
            io:format("Message received from startPid~n"),
            io:format("sending to socket: ~p~n", [Socket]),
            BinaryData = term_to_binary({message, Message}),
            gen_tcp:send(Socket, BinaryData);
        {StartPid, {exit}} ->
            BinaryData = term_to_binary({exit}),
            gen_tcp:send(Socket, BinaryData);
        {StartPid, {show_clients}} ->
            BinaryData = term_to_binary({show_clients}),
            gen_tcp:send(Socket, BinaryData),
            ClientList = get_client_list(ClientStatus),
            io:format("~p~n", [ClientList]),
            print_list(ClientList)
    end,
    loop(ClientStatus).

get_client_list(#client_status{} = ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    gen_tcp:recv(Socket, 0),
    receive
        {tcp, Socket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            {ClientList} = Data,
            ClientList
    end.

send_message() ->
    Message = string:trim(io:get_line("Enter message (or 'exit' to quit): ")),
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {message, Message}}.

send_private_message() ->
    Message = string:trim(io:get_line("Enter message: ")),
    Receiver = string:trim(io:get_line("Enter receiver name: ")),
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {private_message, Message, Receiver}}.

exit() ->
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {exit}}.

show_clients() ->
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {show_clients}}.

help() ->
    % show available commands
    Commands = ["send_message/0", "send_private_message/0", "exit/0", "show_clients/0"],
    print_list(Commands).

print_list(List) ->
    lists:foreach(fun(X) ->
        io:format("~p~n", [X]) end, List).

set_name() ->
    NewName = io:get_line("Enter desired username: "),
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {set_name, NewName}}.
