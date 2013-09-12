%%==============================================================================
%% Copyright 2013 Erlang Solutions Ltd.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

-module(metrics_roster_SUITE).
-compile(export_all).

-include_lib("escalus/include/escalus.hrl").
-include_lib("common_test/include/ct.hrl").


-import(metrics_helper, [assert_counter/2,
                      get_counter_value/1]).

%%--------------------------------------------------------------------
%% Suite configuration
%%--------------------------------------------------------------------

all() ->
    [{group, roster},
     {group, subscriptions}
    ].

groups() ->
    [{roster, [sequence], roster_tests()},
     {subscriptions, [sequence], subscription_tests()}
    ].

suite() ->
    [{required, ejabberd_node} | escalus:suite()].

roster_tests() -> [get_roster,
                   add_contact,
                   roster_push].

subscription_tests() -> [subscribe,
                         unsubscribe,
                         decline_subscription].
%%--------------------------------------------------------------------
%% Init & teardown
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    escalus:init_per_suite(Config).

end_per_suite(Config) ->
    escalus:end_per_suite(Config).

init_per_group(_GroupName, Config) ->
    escalus:create_users(Config).

end_per_group(_GroupName, Config) ->
    escalus:delete_users(Config).

init_per_testcase(CaseName, Config) ->
    escalus:init_per_testcase(CaseName, Config).

end_per_testcase(add_contact, Config) ->
    [{_, UserSpec} | _] = escalus_config:get_config(escalus_users, Config),
    remove_roster(Config, UserSpec),
    escalus:end_per_testcase(add_contact, Config);
end_per_testcase(roster_push, Config) ->
    [{_, UserSpec} | _] = escalus_config:get_config(escalus_users, Config),
    remove_roster(Config, UserSpec),
    escalus:end_per_testcase(roster_push, Config);
end_per_testcase(subscribe, Config) ->
    end_rosters_remove(Config);
end_per_testcase(decline_subscription, Config) ->
    end_rosters_remove(Config);
end_per_testcase(unsubscribe, Config) ->
    end_rosters_remove(Config);
end_per_testcase(CaseName, Config) ->
    escalus:end_per_testcase(CaseName, Config).

end_rosters_remove(Config) ->
    [{_, UserSpec1}, {_, UserSpec2} | _] =
        escalus_config:get_config(escalus_users, Config),
    remove_roster(Config, UserSpec1),
    remove_roster(Config, UserSpec2),
    escalus:end_per_testcase(subscription, Config).

%%--------------------------------------------------------------------
%% Tests
%%--------------------------------------------------------------------

get_roster(Config) ->
    {value, Gets} = get_counter_value(modRosterGets),
    escalus:story(Config, [1, 1], fun(Alice,_Bob) ->

        escalus_client:send(Alice, escalus_stanza:roster_get()),
        escalus_client:wait_for_stanza(Alice),

        assert_counter(Gets + 1, modRosterGets)

        end).

add_contact(Config) ->
    {value, Sets} = get_counter_value(modRosterSets),
    escalus:story(Config, [1, 1], fun(Alice, Bob) ->

        %% add contact
        escalus_client:send(Alice,
                            escalus_stanza:roster_add_contact(Bob,
                                                              [<<"friends">>],
                                                              <<"Bobby">>)),
        Received = escalus_client:wait_for_stanza(Alice),
        escalus_client:send(Alice, escalus_stanza:iq_result(Received)),
        escalus_client:wait_for_stanza(Alice),

        assert_counter(Sets + 1, modRosterSets)

        end).

roster_push(Config) ->
    {value, Pushes} = get_counter_value(modRosterPush),
    escalus:story(Config, [2, 1], fun(Alice1, Alice2, Bob) ->

        %% add contact
        escalus_client:send(Alice1,
                            escalus_stanza:roster_add_contact(Bob,
                                                              [<<"friends">>],
                                                              <<"Bobby">>)),
        Received = escalus_client:wait_for_stanza(Alice1),
        escalus_client:send(Alice1, escalus_stanza:iq_result(Received)),
        escalus_client:wait_for_stanza(Alice1),

        Received2 = escalus_client:wait_for_stanza(Alice2),
        escalus_client:send(Alice2, escalus_stanza:iq_result(Received2)),

        assert_counter(Pushes + 2, modRosterPush)

        end).


subscribe(Config) ->
    {value, Subscriptions} = get_counter_value(modPresenceSubscriptions),
    escalus:story(Config, [1, 1], fun(Alice,Bob) ->

        %% add contact
        add_sample_contact(Alice, Bob),

        %% subscribe
        escalus_client:send(Alice, escalus_stanza:presence_direct(bob, <<"subscribe">>)),
        PushReq = escalus_client:wait_for_stanza(Alice),
        escalus_client:send(Alice, escalus_stanza:iq_result(PushReq)),

        %% Bob receives subscription reqest
        escalus_client:wait_for_stanza(Bob),

        %% Bob adds new contact to his roster
        escalus_client:send(Bob,
                            escalus_stanza:roster_add_contact(Alice,
                                                              [<<"enemies">>],
                                                              <<"Alice">>)),
        PushReqB = escalus_client:wait_for_stanza(Bob),
        escalus_client:send(Bob, escalus_stanza:iq_result(PushReqB)),
        escalus_client:wait_for_stanza(Bob),

        %% Bob sends subscribed presence
        escalus_client:send(Bob, escalus_stanza:presence_direct(alice, <<"subscribed">>)),

        %% Alice receives subscribed
        escalus_client:wait_for_stanzas(Alice, 3),

        %% Bob receives roster push
        escalus_client:wait_for_stanza(Bob),

        assert_counter(Subscriptions +1, modPresenceSubscriptions)

        end).

decline_subscription(Config) ->
    {value, Subscriptions} = get_counter_value(modPresenceUnsubscriptions),
    escalus:story(Config, [1, 1], fun(Alice,Bob) ->

        %% add contact
        add_sample_contact(Alice, Bob),

        %% subscribe
        escalus_client:send(Alice, escalus_stanza:presence_direct(bob, <<"subscribe">>)),
        PushReq = escalus_client:wait_for_stanza(Alice),
        escalus_client:send(Alice, escalus_stanza:iq_result(PushReq)),

        %% Bob receives subscription reqest
        escalus_client:wait_for_stanza(Bob),

        %% Bob refuses subscription
        escalus_client:send(Bob, escalus_stanza:presence_direct(alice, <<"unsubscribed">>)),

        %% Alice receives subscribed
        escalus_client:wait_for_stanzas(Alice, 2),

        assert_counter(Subscriptions +1, modPresenceUnsubscriptions)

        end).


unsubscribe(Config) ->
    {value, Subscriptions} = get_counter_value(modPresenceUnsubscriptions),
    escalus:story(Config, [1, 1], fun(Alice,Bob) ->

        %% add contact
        add_sample_contact(Alice, Bob),

        %% subscribe
        escalus_client:send(Alice, escalus_stanza:presence_direct(bob, <<"subscribe">>)),
        PushReq = escalus_client:wait_for_stanza(Alice),
        escalus_client:send(Alice, escalus_stanza:iq_result(PushReq)),

        %% Bob receives subscription reqest
        escalus_client:wait_for_stanza(Bob),
        %% Bob adds new contact to his roster
        escalus_client:send(Bob,
                            escalus_stanza:roster_add_contact(Alice,
                                                              [<<"enemies">>],
                                                              <<"Alice">>)),
        PushReqB = escalus_client:wait_for_stanza(Bob),
        escalus_client:send(Bob, escalus_stanza:iq_result(PushReqB)),
        escalus_client:wait_for_stanza(Bob),

        %% Bob sends subscribed presence
        escalus_client:send(Bob, escalus_stanza:presence_direct(alice, <<"subscribed">>)),

        %% Alice receives subscribed
        escalus_client:wait_for_stanzas(Alice, 2),

        escalus_client:wait_for_stanza(Alice),

        %% Bob receives roster push
        PushReqB1 = escalus_client:wait_for_stanza(Bob),
        escalus_assert:is_roster_set(PushReqB1),

        %% Alice sends unsubscribe
        escalus_client:send(Alice, escalus_stanza:presence_direct(bob, <<"unsubscribe">>)),

        PushReqA2 = escalus_client:wait_for_stanza(Alice),
        escalus_client:send(Alice, escalus_stanza:iq_result(PushReqA2)),

        %% Bob receives unsubscribe

        escalus_client:wait_for_stanzas(Bob, 2),

        assert_counter(Subscriptions +1, modPresenceUnsubscriptions)

    end).

%%-----------------------------------------------------------------
%% Helpers
%%-----------------------------------------------------------------

add_sample_contact(Alice, Bob) ->
    add_sample_contact(Alice, Bob, [<<"friends">>], <<"generic :p name">>).

add_sample_contact(Alice, Bob, Groups, Name) ->
    escalus_client:send(Alice,
        escalus_stanza:roster_add_contact(Bob, Groups, Name)),
    Received = escalus_client:wait_for_stanza(Alice),
    escalus_client:send(Alice, escalus_stanza:iq_result(Received)),
    escalus_client:wait_for_stanza(Alice).


remove_roster(Config, UserSpec) ->
    [Username, Server, _Pass] = escalus_users:get_usp(Config, UserSpec),
    rpc:call(ejabberd@localhost, mod_roster_odbc, remove_user, [Username, Server]),
    rpc:call(ejabberd@localhost, mod_roster, remove_user, [Username, Server]).
