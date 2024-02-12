-module(client).
-export([start/0, send_message/0, loop/1, exit/0, start_helper/1, send_private_message/0, show_clients/0, help/0, kick/0]).
-record(client_status, {name, serverSocket, startPid, spawnedPid, adminStatus = false}).

start() ->
    ClientStatus = #client_status{startPid = self()},
    SpawnedPid = spawn(client, start_helper, [ClientStatus]),
    put(spawnedPid, SpawnedPid),
    put(startPid, self()).

start_helper(ClientStatus) ->
    {ok, Socket} = gen_tcp:connect('localhost', 9991, [binary, {active, true}]),
    gen_tcp:recv(Socket, 0),
    receive
        {tcp, Socket, BinaryData} ->
            Data = erlang:binary_to_term(BinaryData),
            case Data of
                {connected, Name, MessageHistory} ->
                    io:format("connected to server, with username ~p~n", [Name]),
                    io:format("Message History: ~n"),
                    print_list(MessageHistory),
                    ClientStatus1 = ClientStatus#client_status{serverSocket = Socket, name = Name},
                    loop(ClientStatus1);
                {reject, Message} ->
                    io:format("Error : ~s~n",[Message])
            end;
        {tcp_closed, Socket} ->
            io:format("Not connected to the server: ~n")
    end.

loop(ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    StartPid = ClientStatus#client_status.startPid,
    gen_tcp:recv(Socket, 0),    % activate listening
    receive
        {tcp, Socket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            case Data of
                {message, SenderName, Message} ->
                    io:format("Received: ~p from user ~p~n", [Message, SenderName]);
                {admin, NewAdminStatus} ->
                    ClientStatus1 = ClientStatus#client_status{adminStatus = NewAdminStatus},
                    case NewAdminStatus of
                        true ->
                            io:format("Admin rights received !!~n");
                        false ->
                            io:format("Admin rights revoked !!~n")
                    end,
                    loop(ClientStatus1);
                _ ->
                    io:format("Undefined message received~n")
            end;
        {tcp_closed, Socket} ->
            io:format("Connection closed~n"),
            ok;
        {StartPid, Data} ->
            case Data of
                {private_message, Message, Receiver} ->
                    BinaryData = term_to_binary({private_message, Message, Receiver}),
                    gen_tcp:send(Socket, BinaryData),
                    private_message_helper(ClientStatus);
                {message, Message} ->
                    BinaryData = term_to_binary({message, Message}),
                    gen_tcp:send(Socket, BinaryData);
                {exit} ->
                    BinaryData = term_to_binary({exit}),
                    gen_tcp:send(Socket, BinaryData); 
                {show_clients} ->
                    BinaryData = term_to_binary({show_clients}),
                    gen_tcp:send(Socket, BinaryData),
                    ClientList = get_client_list(ClientStatus),
                    FormattedClientList = lists:map(fun({client, _, Name}) ->
                        Name
                        end, ClientList),
                    print_list(FormattedClientList);
                {kick, ClientName} ->
                    kick_helper(ClientStatus, ClientName)
            end
    end,
    loop(ClientStatus).

kick_helper(ClientStatus, ClientName) ->
    Socket = ClientStatus#client_status.serverSocket,
    AdminStatus = ClientStatus#client_status.adminStatus,
    case AdminStatus of
        true ->
            BinaryData = term_to_binary({kick, ClientName}),
            gen_tcp:send(Socket, BinaryData);
        false ->
            io:format("Admin rights not available~n")
    end.

private_message_helper(#client_status{} = ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    gen_tcp:recv(Socket, 0),
    receive
        {tcp, Socket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            case Data of
                {success, _Message} ->
                    ok;
                {error, Message} ->
                    io:format("Error : ~s~n",[Message])
            end
    end.

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
    Message = string:trim(io:get_line("Enter message: ")),
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

kick() ->
    ClientName = string:trim(io:get_line("Enter Client Name: ")),
    StartPid = get(startPid),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {kick, ClientName}}.


% ----------------------------------









% ----------Unused functions-------------

% set_name() ->
%     NewName = string:trim(io:get_line("Enter desired username: ")),
%     StartPid = get(startPid),
%     SpawnedPid = get(spawnedPid),
%     SpawnedPid ! {StartPid, {set_name, NewName}}.



% set_name_handler(#client_status{} = ClientStatus, NewName) ->
%     io:format("70"),
%     Socket = ClientStatus#client_status.serverSocket,
%     gen_tcp:recv(Socket, 0),
%     receive
%         {tcp, Socket, BinaryData} ->
%             Data = binary_to_term(BinaryData),
%             io:format("Data received: ~p~n", Data),
%             case Data of
%                 {error, Message} ->
%                     io:format("error while updating username: ~p~n", [Message]),
%                     ClientStatus;
%                 {success, _Message} ->
%                     io:format("username updated to ~p~n", [NewName]),
%                     ClientStatus1 = ClientStatus#client_status{name = NewName},
%                     ClientStatus1
%             end
%     end.


% {StartPid, {set_name, NewName}} ->
%     BinaryData = term_to_binary({set_name, NewName}),
%     gen_tcp:send(Socket, BinaryData),
%     set_name_handler(ClientStatus, NewName)
