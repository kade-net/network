/**
    * This module is responsible for handling all user generated content and emiting events without storage,
    * The main focus of this module is to provide events that off chain clients can use to reconstruct the network's state
    * only downside of not storing state is, we won't be able to validate references, the clients have been built to account for the possibility that users may mistakenly or intentionaly try to make references to data that does not exist.
**/

module kade::publications {

    use std::signer;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use kade::accounts;
    #[test_only]
    use std::features;
    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use kade::usernames;

    const SEED: vector<u8> = b"kade::publicationsv1.0.3";

    const EOperationNotPermitted: u64 = 101;

    struct State has key {
        publication_count: u64,
        reaction_count: u64,
        comment_count: u64,
        repost_count: u64,
        quoute_count: u64,
        signer_capability:  account::SignerCapability,
        publication_create_events: event::EventHandle<PublicationCreate>,
        publication_remove_events: event::EventHandle<PublicationRemove>,
        comment_create_events: event::EventHandle<CommentCreateEvent>,
        comment_remove_events: event::EventHandle<CommentRemoveEvent>,
        repost_create_events: event::EventHandle<RepostCreateEvent>,
        repost_remove_events: event::EventHandle<RepostRemoveEvent>,
        quote_create_events: event::EventHandle<QuoteCreateEvent>,
        quote_remove_events: event::EventHandle<QuoteRemoveEvent>,
        reaction_create_events: event::EventHandle<ReactionCreateEvent>,
        reaction_remove_events: event::EventHandle<ReactionRemoveEvent>
    }


    #[event]
    struct PublicationCreate has store, drop {
        kid: u64,
        payload: string::String,  // stringified json payload
        user_kid: u64,
        delegate: address,
        timestamp: u64
    }

    #[event]
    struct  PublicationRemove has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct CommentCreateEvent has store, drop {
        kid: u64,
        reference_kid: u64,
        user_kid: u64,
        delegate: address,
        type: u64, // comment 1 for comment on publication, 2 for comment on quoute, 3 for comment on comment
        timestamp: u64,
        content: string::String
    }

    #[event]
    struct CommentRemoveEvent has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct  RepostCreateEvent has store, drop {
        kid: u64,
        reference_kid: u64,
        type: u64, // 1 for publication, 2 for quotes , 3 for comments
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct RepostRemoveEvent has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct QuoteCreateEvent has store, drop {
        kid: u64,
        reference_kid: u64,
        user_kid: u64,
        delegate: address,
        payload: string::String,
        timestamp: u64,
    }

    #[event]
    struct QuoteRemoveEvent has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct ReactionCreateEvent has store, drop {
        kid: u64,
        reference_kid: u64,
        type: u64,// 1 for publication, 2 for quotes , 3 for comments
        user_kid: u64,
        delegate: address,
        reaction: u64,
        timestamp: u64,
    }

    #[event]
    struct ReactionRemoveEvent has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }


    fun init_module(admin: &signer) {
        let (resource_signer, signer_capability ) = account::create_resource_account(admin, SEED);

        move_to(&resource_signer, State {
            signer_capability,
            repost_count: 0,
            reaction_count: 0,
            comment_count: 0,
            publication_count: 0,
            quoute_count: 0,
            comment_create_events: account::new_event_handle(&resource_signer),
            comment_remove_events: account::new_event_handle(&resource_signer),
            publication_create_events: account::new_event_handle(&resource_signer),
            publication_remove_events: account::new_event_handle(&resource_signer),
            quote_create_events: account::new_event_handle(&resource_signer),
            quote_remove_events: account::new_event_handle(&resource_signer),
            reaction_create_events: account::new_event_handle(&resource_signer),
            reaction_remove_events: account::new_event_handle(&resource_signer),
            repost_create_events: account::new_event_handle(&resource_signer),
            repost_remove_events: account::new_event_handle(&resource_signer),
        });

    }


    public entry fun create_publication(delegate: &signer, payload: string::String) acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.publication_count;
        state.publication_count = state.publication_count + 1;

        event::emit_event(&mut state.publication_create_events, PublicationCreate {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            payload,
            user_kid
        });
    }

    // DEFER GAS FEES
    public entry fun gd_create_publication(admin: &signer, delegate: &signer, payload: string::String) acquires State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        create_publication(delegate, payload);
    }



    public entry fun remove_publication(delegate: &signer, kid: u64) acquires State {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.publication_remove_events, PublicationRemove {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    public entry fun create_comment(delegate: &signer, reference_kid: u64, type: u64, content: string::String) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.comment_count;
        state.comment_count = state.comment_count + 1;

        event::emit_event(&mut state.comment_create_events, CommentCreateEvent {
            delegate: delegate_address,
            kid,
            reference_kid,
            timestamp: timestamp::now_seconds(),
            type,
            user_kid,
            content
        });
    }

    // DEFER GAS FEES
    public entry fun gd_create_comment(admin: &signer, delegate: &signer, reference_kid: u64, type: u64, content: string::String) acquires State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        create_comment(delegate, reference_kid, type, content);
    }

    public entry fun remove_comment(delegate: &signer, kid: u64) acquires State {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.comment_remove_events, CommentRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    public entry fun create_repost(delegate: &signer, reference_kid: u64, type: u64) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.repost_count;
        state.repost_count = state.repost_count + 1;


        event::emit_event(&mut state.repost_create_events, RepostCreateEvent {
            delegate: delegate_address,
            kid,
            reference_kid,
            timestamp: timestamp::now_seconds(),
            user_kid,
            type
        })
    }

    // DEFER GAS FEES
    public entry fun gd_create_repost(admin: &signer, delegate: &signer, reference_kid: u64, type: u64) acquires State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        create_repost(delegate, reference_kid, type);
    }

    public entry fun remove_repost(delegate: &signer, kid: u64) acquires State {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);

        let resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.repost_remove_events, RepostRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    public entry fun create_quote(delegate: &signer, reference_kid: u64, payload: string::String) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.quoute_count;
        state.quoute_count = state.quoute_count + 1;

        event::emit_event(&mut state.quote_create_events, QuoteCreateEvent {
            delegate: delegate_address,
            kid,
            reference_kid,
            timestamp: timestamp::now_seconds(),
            user_kid,
            payload
        });
    }

    // DEFER GAS FEES
    public entry fun gd_create_quote(admin: &signer, delegate: &signer, reference_kid: u64, payload: string::String) acquires State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        create_quote(delegate, reference_kid, payload);
    }

    public entry fun remove_quote(delegate: &signer, kid: u64) acquires State {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.quote_remove_events, QuoteRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    public entry fun create_reaction(delegate: &signer, reaction: u64, reference_kid: u64, type: u64) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.reaction_count;
        state.reaction_count = state.reaction_count + 1;

        event::emit_event(&mut state.reaction_create_events, ReactionCreateEvent {
            delegate: delegate_address,
            kid,
            reaction,
            timestamp: timestamp::now_seconds(),
            user_kid,
            reference_kid,
            type
        });
    }

    // DEFER GAS FEES
    public entry fun gd_create_reaction(admin: &signer, delegate: &signer, reaction: u64, reference_kid: u64, type: u64) acquires State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        create_reaction(delegate, reaction, reference_kid, type);
    }

    public entry fun remove_reaction(delegate: &signer, kid: u64) acquires State {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.reaction_remove_events, ReactionRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }



    // ====
    // Tests
    // ====

    #[test(admin = @kade)]
    fun test_init_module(admin: &signer) acquires  State {

        init_module(admin);

        let resource_address = account::create_resource_address(&@kade, SEED);

        debug::print(&resource_address);

        let state = borrow_global<State>(resource_address);

        assert!(state.publication_count == 0,1);
        assert!(state.reaction_count == 0,2);
        assert!(state.comment_count == 0,3);
        assert!(state.repost_count == 0,4);
        assert!(state.quoute_count == 0,5);

    }

    #[test(admin = @kade)]
    fun test_create_publication(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 1,1);




    }


    #[test(admin = @kade)]
    fun test_remove_publication(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 1,1);

    }


    #[test(admin = @kade)]
    fun test_create_comment(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_comment(&delegate, 0, 1, string::utf8(b"COOL"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.comment_count == 1,1);

    }

    #[test(admin = @kade)]
    fun test_remove_comment(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_comment(&delegate, 0, 1, string::utf8(b"COOL"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.comment_count == 1,1);

    }

    #[test(admin = @kade)]
    fun test_create_repost(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_repost(&delegate, 0, 1);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.repost_count == 1,1);

    }

    #[test(admin = @kade)]
    fun test_remove_repost(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_repost(&delegate, 0, 1);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.repost_count == 1,1);


        remove_repost(&delegate, 0);

    }

    #[test(admin = @kade)]
    fun test_create_quote(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_quote(&delegate, 0, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.quoute_count == 1,1);

    }

    #[test(admin = @kade)]
    fun test_remove_quote(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_quote(&delegate, 0, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.quoute_count == 1,1);

    }

    #[test(admin = @kade)]
    fun test_create_reaction(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_reaction(&delegate, 1, 0, 0);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.reaction_count == 1,1);

    }

    #[test(admin = @kade)]
    fun test_remove_reaction(admin: &signer) acquires State {

        let aptos_framework = account::create_account_for_test(@0x1);
        let user = account::create_account_for_test(@0x2);
        let delegate = account::create_account_for_test(@0x3);
        account::create_account_for_test(@kade);

        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        accounts::invoke_init_module(admin);
        usernames::invoke_init_module(admin);
        init_module(admin);
        usernames::claim_username(&user, string::utf8(b"kade"));
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_reaction(&delegate, 1, 0, 0);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.reaction_count == 1,1);

    }










}
