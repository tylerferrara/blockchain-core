%%%-------------------------------------------------------------------
%% @doc
%% == Blockchain CLI Ledger ==
%% @end
%%%-------------------------------------------------------------------
-module(blockchain_cli_ledger).

-behavior(clique_handler).

-export([register_cli/0]).

register_cli() ->
    register_all_usage()
    ,register_all_cmds().

register_all_usage() ->
    lists:foreach(fun(Args) ->
                          apply(clique, register_usage, Args)
                  end,
                 [
                  ledger_pay_usage()
                  ,ledger_balance_usage()
                  ,ledger_gateways_usage()
                  ,ledger_add_gateway_request_usage()
                  ,ledger_add_gateway_txn_usage()
                  ,ledger_usage()
                 ]).

register_all_cmds() ->
    lists:foreach(fun(Cmds) ->
                          [apply(clique, register_command, Cmd) || Cmd <- Cmds]
                  end,
                 [
                  ledger_pay_cmd()
                  ,ledger_balance_cmd()
                  ,ledger_gateways_cmd()
                  ,ledger_add_gateway_request_cmd()
                  ,ledger_add_gateway_txn_cmd()
                  ,ledger_cmd()
                 ]).

%%--------------------------------------------------------------------
%% ledger
%%--------------------------------------------------------------------
ledger_usage() ->
    [["ledger"],
     ["blockchain ledger commands\n\n",
      "  ledger balance   - Get the balance for this or all addresses.\n"
      "  ledger pay       - Transfer tokens to a crypto address.\n"
      "  ledger gateways  - Display the list of active gateways.\n"
      "  ledger add_gateway_request  - Request the addition of a gateway.\n"
      "  ledger add_gateway_txn  - Countersign the addition of a gateway and submit it.\n"
     ]
    ].

ledger_cmd() ->
    [
     [["ledger"], [], [], fun(_, _, _) -> usage end]
    ].


%%--------------------------------------------------------------------
%% ledger pay
%%--------------------------------------------------------------------
ledger_pay_cmd() ->
    [
     [["ledger", "pay", '*', '*'], [], [], fun ledger_pay/3]
    ].

ledger_pay_usage() ->
    [["ledger", "pay"],
     ["ledger pay <p2p> <amount>\n\n",
      "  Transfer given <amount> to the target <p2p> address.\n"
     ]
    ].

ledger_pay(["ledger", "pay", Addr, Amount], [], []) ->
    case (catch {libp2p_crypto:b58_to_address(Addr),
                 list_to_integer(Amount)}) of
        {'EXIT', _} ->
            usage;
        {Recipient, Value} when Value > 0 ->
            blockchain_worker:spend(Recipient, Value),
            [clique_status:text("ok")];
        _ -> usage
    end;
ledger_pay(_, _, _) ->
    usage.


%%--------------------------------------------------------------------
%% ledger add gateway_request
%%--------------------------------------------------------------------
ledger_add_gateway_request_cmd() ->
    [
     [["ledger", "add_gateway_request", '*'], [], [], fun ledger_add_gateway_request/3]
    ].

ledger_add_gateway_request_usage() ->
    [["ledger", "add_gateway_request"],
     ["ledger add_gateway_request <p2p>\n\n",
      "  Request the addition of the current node as a gateway owned by <p2p>.\n"
     ]
    ].

ledger_add_gateway_request(["ledger", "add_gateway_request", Addr], [], []) ->
    case (catch libp2p_crypto:b58_to_address(Addr)) of
        {'EXIT', _Reason} ->
            usage;
        Owner when is_binary(Owner) ->
            blockchain_worker:add_gateway_request(Owner),
            Txn = blockchain_worker:add_gateway_request(Owner),
            [clique_status:text(base58:binary_to_base58(term_to_binary(Txn)))];
        _ ->
            usage
    end;
ledger_add_gateway_request(_, _, _) ->
    usage.


%%--------------------------------------------------------------------
%% ledger add_gateway_txn
%%--------------------------------------------------------------------
ledger_add_gateway_txn_cmd() ->
    [
     [["ledger", "add_gateway_txn", '*'], [], [], fun ledger_add_gateway_txn/3]
    ].

ledger_add_gateway_txn_usage() ->
    [["ledger", "add_gateway_txn"],
     ["ledger add_gateway_txn <txn>\n\n",
      "  Countersign the add_gateway transaction <txn> and submit it.\n"
     ]
    ].

ledger_add_gateway_txn(["ledger", "add_gateway_txn", AddGatewayRequest], [], []) ->
    case (catch binary_to_term(base58:base58_to_binary(AddGatewayRequest))) of
        {'EXIT', _} ->
            usage;
        Txn ->
            blockchain_worker:add_gateway_txn(Txn),
            [clique_status:text("ok")]
        %_ -> usage
    end;
ledger_add_gateway_txn(_, _, _) ->
    usage.


%%--------------------------------------------------------------------
%% ledger balance
%%--------------------------------------------------------------------
ledger_balance_cmd() ->
    [
     [["ledger", "balance"], [],
      [{all, [{shortname, "a"},
               {longname, "all"}]}
      ], fun ledger_balance/3],
     [["ledger", "balance", '*'], [], [], fun ledger_balance/3]
    ].

ledger_balance_usage() ->
    [["ledger", "balance"],
     ["ledger balance [<p2p> | -a]\n\n",
      "  Retrieve the current balanace for this node, all nodes,\n",
      "  or a given <p2p> node.\n\n"
      "Options\n\n",
      "  -a, --all\n",
      "    Display balances for all known nodes.\n"
     ]
    ].

ledger_balance(["ledger", "balance", Str], [], []) ->
    Ledger = get_ledger(),
    case (catch libp2p_crypto:b58_to_address(Str)) of
        {'EXIT', _} -> usage;
        Addr ->
            R = [format_ledger_balance({Addr, blockchain_ledger:find_entry(Addr, Ledger)})],
            [clique_status:table(R)]
    end;
ledger_balance(_CmdBase, [], []) ->
    Addr = blockchain_swarm:address(),
    Ledger = get_ledger(),
    R = [format_ledger_balance({Addr, blockchain_ledger:find_entry(Addr, Ledger)})],
    [clique_status:table(R)];
ledger_balance(_CmdBase, [], [{all, _}]) ->
    Balances = maps:filter(fun(K, _V) ->
                                   is_binary(K)
                           end, get_ledger()),
    R = [format_ledger_balance(E) || E <- maps:to_list(Balances)],
    [clique_status:table(R)].

-spec format_ledger_balance({libp2p_crypto:address(), blockchain_ledger:entry()}) -> list().
format_ledger_balance({Addr, Entry}) ->
    [{p2p, libp2p_crypto:address_to_p2p(Addr)},
     {nonce, integer_to_list(blockchain_ledger:payment_nonce(Entry))},
     {balance, integer_to_list(blockchain_ledger:balance(Entry))}
    ].

get_ledger() ->
    case blockchain_worker:ledger() of
        undefined -> #{};
        L -> L
    end.

%%--------------------------------------------------------------------
%% ledger gateways
%%--------------------------------------------------------------------
ledger_gateways_cmd() ->
    [
     [["ledger", "gateways"], [], [], fun ledger_gateways/3]
    ].

ledger_gateways_usage() ->
    [["ledger", "gateways"],
     ["ledger gateways\n\n",
      "  Retrieve all currently active gateways and their H3 index.\n"
     ]
    ].

ledger_gateways(_CmdBase, [], []) ->
    Gateways = maps:get(active_gateways, get_ledger(), #{}),
    R = [format_ledger_gateway_entry(G) || G <- maps:to_list(Gateways)],
    [clique_status:table(R)].

format_ledger_gateway_entry({GatewayAddr, {gw_info, OwnerAddr, Index, Nonce}}) ->
    IndexToStr = fun(undefined) -> "undefined";
                    (I) -> I
                 end,
    [{owner_address, libp2p_crypto:address_to_p2p(OwnerAddr)},
     {gateway_address, libp2p_crypto:address_to_p2p(GatewayAddr)},
     {nonce, Nonce},
     {h3_index, IndexToStr(Index)}
    ].