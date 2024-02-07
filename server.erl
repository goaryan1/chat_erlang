-module(server).
-export([start/0, loop/1, accept_clients/2, broadcast/1, broadcast/2, remove_client/1, show_clients/0, print_messages/1]).
-record(client, {clientSocket, clientName}).
-record(message, {timestamp, senderName, text}). %senderName connects with #client.clientName
-include_lib("stdlib/include/qlc.hrl").

start() ->
    init_databases(),
    {ok, ListenSocket} = gen_tcp:listen(9990, [binary, {packet, 0}, {active, false}]),
    io:format("Server listening on port 9990 and Socket : ~p ~n",[ListenSocket]),
    Counter = 1,
    spawn(server, accept_clients, [ListenSocket, Counter]).

init_databases() ->
    mnesia:start(),
    mnesia:create_table(client, [{attributes, record_info(fields, client)}]),
    mnesia:create_table(message, [{attributes, record_info(fields, message)}, {type, ordered_set}]).

accept_clients(ListenSocket, Counter) ->
    io:format("Function Accept Clients ~n"),
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    ClientName = "User" ++ integer_to_list(Counter),
    io:format("Accepted connection from ~p~n", [ClientName]),
    Data = {connected, ClientName},
    BinaryData = erlang:term_to_binary(Data),
    gen_tcp:send(ClientSocket, BinaryData),
    spawn(server, loop, [ClientSocket]),
    insert_client_database(ClientSocket, ClientName),
    Message = "User " ++ ClientName ++ " joined the ChatRoom.",
    broadcast({ClientSocket, Message}),
    NewCounter = Counter + 1,
    accept_clients(ListenSocket, NewCounter).

insert_client_database(ClientSocket, ClientName) ->
    ClientRecord = #client{clientSocket=ClientSocket, clientName = ClientName},
    mnesia:transaction(fun() ->
        mnesia:write(ClientRecord)
    end).

insert_message_database(ClientName, Message) ->
    io:format("Data Inserted ~n"),
        MessageRecord = #message{timestamp = os:timestamp(), senderName = ClientName, text = Message},
        mnesia:transaction(fun() ->
            mnesia:write(MessageRecord)
        end).

% userNameUsed(UserName) ->
%     case mnesia:dirty_read({client, UserName}) of
%         [] ->
%             false;
%         [_] ->
%             true
%     end.

getUserName(ClientSocket) ->
    Trans = fun() -> mnesia:read({client, ClientSocket}) end, 
    {atomic,[Record]} = mnesia:transaction(Trans),
    Record#client.clientName.

getSocket(Name) ->
    Query = qlc:q([{User#client.clientSocket} || User <- mnesia:table(client), User#client.clientName == Name]),
    case mnesia:transaction(fun() -> qlc:e(Query) end) of
        {atomic, [Socket]} ->
            {X} = Socket,
            X;
        {atomic, []} ->
            {error, not_found};
        {aborted, Reason} ->
            {error, Reason}
    end.

loop(ClientSocket) ->
    gen_tcp:recv(ClientSocket, 0),  % Activate passive mode for the client socket
    receive
        % Received a Message
        {tcp, ClientSocket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            case Data of
                % Private Message
                {message, Message, Receiver} ->
                    io:format("Client ~p send message to ~p : ~p~n", [getUserName(ClientSocket), Receiver, Message]),
                    broadcast({ClientSocket, Message}, Receiver),
                    loop(ClientSocket);
                % Broadcast Message
                {message, Message} ->
                    io:format("Received from ~p: ~s~n",[getUserName(ClientSocket),Message]),
                    broadcast({ClientSocket,Message}),
                    loop(ClientSocket); 
                % Send list of Active Clients 
                {show_clients} ->
                    List = show_clients(),
                    gen_tcp:send(ClientSocket, term_to_binary({List})),
                    loop(ClientSocket);
                % Exit from ChatRoom
                {exit} ->
                    io:format("Client ~p left the ChatRoom.~n",[getUserName(ClientSocket)]),
                    LeavingMessage = getUserName(ClientSocket) ++ " left the ChatRoom.",
                    broadcast({ClientSocket, LeavingMessage}),
                    remove_client(ClientSocket)
            end;
        % Client Connection lost
        {tcp_closed, ClientSocket} ->
            io:format("Client ~p disconnected~n", [getUserName(ClientSocket)]),
            remove_client(ClientSocket)
    end.

broadcast({SenderSocket, Message}, Receiver) ->
    % private messages don't get saved in the database
    RecSocket = getSocket(Receiver),
    SenderName = getUserName(SenderSocket),
    gen_tcp:send(RecSocket, term_to_binary({message, SenderName, Message})).

broadcast({SenderSocket, Message}) ->
    SenderName = getUserName(SenderSocket),
    insert_message_database(SenderName, Message),
    Keys = mnesia:dirty_all_keys(client),
    lists:foreach(fun(ClientSocket) ->
        case ClientSocket/=SenderSocket of
            true ->
                case mnesia:dirty_read({client, ClientSocket}) of
                [_] ->
                    io:format("Broadcasted the Message~n"),
                    gen_tcp:send(ClientSocket, term_to_binary({message, SenderName, Message}));
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

show_clients() ->
    Keys = mnesia:dirty_all_keys(client),
    Clients_list = lists:foreach( fun(X) ->
        Trans = fun() -> mnesia:read({client, X}) end,
        {atomic,[ClientRecord]} = mnesia:transaction(Trans), 
        ClientName = ClientRecord#client.clientName,
        io:format("ClientName: ~p, ClientSocket: ~p~n", [ClientName, X])
        end, Keys),
    Clients_list.

print_messages(N) ->
    F = fun() ->
        qlc:e(qlc:q([M || M <- mnesia:table(message)]))
    end,
    {atomic, Query} = mnesia:transaction(F),
    ReverseMessages = lists:sublist(lists:reverse(Query), 1, N),
    Messages = lists:reverse(ReverseMessages),
    lists:foreach(fun(X) ->
        io:format("~p~n", [X]) end, Messages).
