-module(server).
-export([start/0, handle_client/1, accept_clients/1, broadcast/1, remove_client/1]).
-record(client, {clientSocket,clientName}).


init_mnesia() ->
    mnesia:start(),
    mnesia:create_schema([node()]),
    mnesia:create_table(client, [{attributes, record_info(fields, client)}]).

% Inserting Data into mnesia_db
insert_client_into_mnesia({ClientSocket, ClientName}) ->
    io:format("Data Inserted ~n"),
    ClientRecord = #client{clientSocket=ClientSocket, clientName = ClientName},
    mnesia:transaction(fun() ->
        mnesia:write(ClientRecord)
    end).

start() ->
    init_mnesia(),
    {ok, ListenSocket} = gen_tcp:listen(9990, [binary, {packet, 0}, {active, false}]),
    io:format("Server listening on port 9990 and Socket : ~p ~n",[ListenSocket]),
    spawn(server, accept_clients, [ListenSocket]).

userNameUsed(UserName) ->
    case mnesia:dirty_read({client, UserName}) of
        [] ->
            false;
        [_] ->
            true
    end.

getUserName(ClientSocket) ->
    case mnesia:dirty_read({client_table, ClientSocket}) of
        [] ->
            {error, not_found};
        [{ClientSocket, ClientName}] ->
            {ok, ClientName}
    end.

getSocket(ClientName) ->
    case mnesia:dirty_read({client_table, '$1', ClientName}) of
        [] ->
            {error, not_found};
        [{ClientSocket, _ClientName}] ->
            {ok, ClientSocket}
    end.

accept_clients(ListenSocket) ->
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    case gen_tcp:recv(ClientSocket, 0) of
        {ok, ClientName} ->
            case userNameUsed(ClientName) of
                true ->
                    % Connection Rejected
                    gen_tcp:send(ClientSocket, <<"Oops!! UserName Already in Use, Try Different UserName.">>),
                    gen_tcp:close(ClientSocket);
                false ->
                    io:format("Accepted connection from ~p~n", [ClientName]),
                    gen_tcp:send(ClientSocket, <<"Hello, ",ClientName/binary, "!">>),
                    Pid = spawn(server, handle_client, [ClientSocket]),
                    gen_tcp:controlling_process(ClientSocket, Pid),
                    insert_client_into_mnesia({ClientSocket, ClientName}),
                    Message = ClientName ++ " joined the ChatRoom.",
                    broadcast({ClientSocket, Message})
            end;
        {error, Reason} ->
            io:format("Error receiving data ~p~n",{Reason}),
            gen_tcp:close(ClientSocket)
    end,
    accept_clients(ListenSocket).

handle_client(ClientSocket) ->
    gen_tcp:recv(ClientSocket, 0),  % Activate passive mode for the client socket
    receive
        {tcp, ClientSocket, {message, Message, Receiver}} ->
            io:format("Client ~p send message to ~p : ~p~n", [getUserName(ClientSocket), Receiver, Message]),
            broadcast({ClientSocket, Message}, Receiver),
            handle_client(ClientSocket);
        {tcp, ClientSocket, {all, Message}} ->
            io:format("Received from ~p: ~s~n",[getUserName(ClientSocket),Message]),
            broadcast({ClientSocket,Message});    
        {tcp, ClientSocket, {exit}} ->
            io:format("Client ~p left the ChatRoom.~n",[getUserName(ClientSocket)]),
            LeavingMessage = getUserName(ClientSocket) ++ " left the ChatRoom.",
            broadcast({ClientSocket, LeavingMessage}),
            remove_client(ClientSocket);    
        {tcp_closed, ClientSocket} ->
            io:format("Client ~p disconnected~n", [getUserName(ClientSocket)]),
            remove_client(ClientSocket)
    end.

broadcast({SenderSocket, Message}, Receiver) ->
    RecSocket = getSocket(Receiver),
    SenderName = getUserName(SenderSocket),
    gen_tcp:send(RecSocket, {SenderName, Message}).

broadcast({SenderSocket, Message}) ->
    Keys = mnesia:dirty_all_keys(client),
    SenderName = getUserName(SenderSocket),
    lists:foreach(fun(ClientSocket) ->
        case ClientSocket/=SenderSocket of
            true ->
                case mnesia:dirty_read({client, ClientSocket}) of
                [_] ->
                    gen_tcp:send(ClientSocket, {SenderName,Message});
                [] ->
                    io:format("No receiver Found ~n") 
                end;
            false -> ok
            end
        end, Keys).
    
    

remove_client(ClientSocket) ->
    ClientName = getUserName(ClientSocket),
    ClientRecord = #client{clientSocket = ClientSocket, clientName = ClientName},
    mnesia:transaction(fun() ->
        mnesia:delete_object(ClientRecord)
    end),
    gen_tcp:close(ClientSocket).
