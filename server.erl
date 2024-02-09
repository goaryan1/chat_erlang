-module(server).
-export([start/0, accept_clients/3, broadcast/1, broadcast/2, remove_client/1, show_clients/0, print_messages/1, loop/1]).
-record(client, {clientSocket, clientName}).
-record(message, {timestamp, senderName, text}). %senderName corresponds to #client.clientName
-include_lib("stdlib/include/qlc.hrl").

start() ->
    init_databases(),
    {N,[]} =  string:to_integer(string:trim(io:get_line("Enter No of Clients Allowed : "))),
    {ok, ListenSocket} = gen_tcp:listen(9991, [binary, {packet, 0}, {active, true}]),
    io:format("Server listening on port 9990 and Socket : ~p ~n",[ListenSocket]),
    Counter = 1,
    spawn(server, accept_clients, [ListenSocket, Counter, N]).

init_databases() ->
    mnesia:start(),
    mnesia:create_table(client, [{attributes, record_info(fields, client)}]),
    mnesia:create_table(message, [{attributes, record_info(fields, message)}, {type, ordered_set}]).

accept_clients(ListenSocket, Counter, N) ->
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    Active_clients = active_clients(),
    io:format("~p~n",[Active_clients]),
    if 
        Active_clients<N ->
            ClientName = "User" ++ integer_to_list(Counter),
            io:format("Accepted connection from ~p~n", [ClientName]),
            Data = {connected, ClientName},
            BinaryData = erlang:term_to_binary(Data),
            gen_tcp:send(ClientSocket, BinaryData),
            insert_client_database(ClientSocket, ClientName),
            Message = ClientName ++ " joined the ChatRoom.",
            broadcast({ClientSocket, Message}),
            NewCounter = Counter + 1,
            ListenPid = spawn(server, loop, [ClientSocket]),
            gen_tcp:controlling_process(ClientSocket, ListenPid),
            accept_clients(ListenSocket, NewCounter, N);
        true->
            Message = "No Space on Server :(",
            gen_tcp:send(ClientSocket, Message),
            gen_tcp:close(ClientSocket),
            accept_clients(ListenSocket, Counter, N)
    end.

    

loop(ClientSocket) ->
    gen_tcp:recv(ClientSocket, 0),
    receive
        {tcp, ClientSocket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            io:format("Message received: ~p~n", [Data]),
            case Data of
                % Private Message
                {private_message, Message, Receiver} ->
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
                    io:format("~p~n",[List]),
                    loop(ClientSocket);
                % Exit from ChatRoom
                {exit} ->
                    io:format("Client ~p left the ChatRoom.~n",[getUserName(ClientSocket)]),
                    LeavingMessage = getUserName(ClientSocket) ++ " left the ChatRoom.",
                    broadcast({ClientSocket, LeavingMessage}),
                    remove_client(ClientSocket);
                {set_name, NewName} ->
                    io:format("inside set_name~n"),
                    case userNameUsed(NewName) of
                        true ->
                            io:format("name is used~n"),
                            gen_tcp:send(ClientSocket, term_to_binary({error, "Name already in use"}));
                        false ->
                            io:format("name is unused~n"),
                            updateName(ClientSocket, NewName),
                            gen_tcp:send(ClientSocket, term_to_binary({success, "Name updated to " ++ NewName}))
                end
            end;
        % Client Connection lost
        {tcp_closed, ClientSocket} ->
            io:format("Client ~p disconnected~n", [getUserName(ClientSocket)]),
            remove_client(ClientSocket)
    end.

updateName(ClientSocket, NewName) ->
    mnesia:write(#client{clientName =  NewName, clientSocket = ClientSocket}).

insert_client_database(ClientSocket, ClientName) ->
    ClientRecord = #client{clientSocket=ClientSocket, clientName = ClientName},
    mnesia:transaction(fun() ->
        mnesia:write(ClientRecord)
    end).

insert_message_database(ClientName, Message) ->

        MessageRecord = #message{timestamp = os:timestamp(), senderName = ClientName, text = Message},
        mnesia:transaction(fun() ->
            mnesia:write(MessageRecord)
        end).

userNameUsed(UserName) ->
    case mnesia:dirty_read({client, UserName}) of
        [] ->
            false;
        [_] ->
            true
    end.

active_clients() ->
    Trans = fun() -> mnesia:all_keys(client) end,
    {atomic,List} = mnesia:transaction(Trans),
    No_of_clients = length(List),
    No_of_clients.

getUserName(ClientSocket) ->
    Trans = fun() -> mnesia:read({client, ClientSocket}) end, 
    {atomic,[Record]} = mnesia:transaction(Trans),
    Record#client.clientName.

getSocket(Name) ->
    Query = qlc:q([User#client.clientSocket || User <- mnesia:table(client), User#client.clientName == Name]),
    Trans = mnesia:transaction(fun() -> qlc:e(Query) end),
    case Trans of
        {atomic, [Socket]} ->
            Socket;
        {atomic, []} ->
            {error, not_found};
        {aborted, Reason} ->
            {error, Reason}
    end.

broadcast({SenderSocket, Message}, Receiver) ->
    % private messages don't get saved in the database
    io:format("receiver : ~p~n", [Receiver]),
    RecSocket = getSocket(Receiver),
    SenderName = getUserName(SenderSocket),
    io:format("RecScoket : ~p, Sendername : ~p~n",[RecSocket, SenderName]),
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
    mnesia:transaction(fun() ->
        {atomic, Rows} = mnesia:dirty_all_keys(client),
        lists:map(fun(Key) ->
            {atomic, Value} = mnesia:dirty_read({client, Key}),
            Value
        end, Rows)
    end).


print_messages(N) ->
    F = fun() ->
        qlc:e(qlc:q([M || M <- mnesia:table(message)]))
    end,
    {atomic, Query} = mnesia:transaction(F),
    ReverseMessages = lists:sublist(lists:reverse(Query), 1, N),
    Messages = lists:reverse(ReverseMessages),
    lists:foreach(fun(X) ->
        io:format("~p~n", [X]) end, Messages).
