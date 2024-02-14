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
    use std::vector;
    #[test_only]
    use aptos_framework::event::emitted_events;

    const SEED: vector<u8> = b"kade::publicationsv1.0.0";

    struct State has key {
        publication_count: u256,
        reaction_count: u256,
        comment_count: u256,
        repost_count: u256,
        quoute_count: u256,
        signer_capability:  account::SignerCapability,
    }


    #[event]
    struct PublicationCreate has store, drop {
        kid: u256,
        payload: string::String,  // stringified json payload
        user_kid: u64,
        delegate: address,
        timestamp: u64
    }

    #[event]
    struct  PublicationRemove has store, drop {
        kid: u256,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct CommentCreateEvent has store, drop {
        kid: u256,
        refference_kid: u256,
        user_kid: u64,
        delegate: address,
        type: u64, // comment 1 for comment on publication, 2 for comment on quoute, 3 for comment on comment
        timestamp: u64,
    }

    #[event]
    struct CommentDeleteEvent has store, drop {
        kid: u256,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct  RepostCreateEvent has store, drop {
        kid: u256,
        refference_kid: u256,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct RepostRemoveEvent has store, drop {
        kid: u256,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct QuoteCreateEvent has store, drop {
        kid: u256,
        reference_kid: u256,
        user_kid: u64,
        delegate: address,
        payload: string::String,
        timestamp: u64,
    }

    #[event]
    struct QuoteRemoveEvent has store, drop {
        kid: u256,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct ReactionCreateEvent has store, drop {
        kid: u256,
        user_kid: u64,
        delegate: address,
        reaction: u64,
        timestamp: u64,
    }

    #[event]
    struct ReactionRemoveEvent has store, drop {
        kid: u256,
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
            quoute_count: 0
        });

    }


    public entry fun create_publication(delegate: &signer, payload: string::String) acquires  State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.publication_count;
        state.publication_count = state.publication_count + 1;

        event::emit(PublicationCreate {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            payload,
            user_kid
        })
    }


    public entry fun remove_publication(delegate: &signer, kid: u256) {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);


        event::emit(PublicationRemove {
            delegate: delegate_address,
            timestamp: timestamp::now_seconds(),
            kid,
            user_kid
        })
    }

    public entry fun create_comment(delegate: &signer, refference_kid: u256, type: u64) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.comment_count;
        state.comment_count = state.comment_count + 1;

        event::emit(CommentCreateEvent {
            delegate: delegate_address,
            kid,
            refference_kid,
            timestamp: timestamp::now_seconds(),
            type,
            user_kid
        })
    }

    public entry fun remove_comment(delegate: &signer, kid: u256) {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);

        event::emit(CommentDeleteEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun create_repost(delegate: &signer, refference_kid: u256) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.repost_count;
        state.repost_count = state.repost_count + 1;

        event::emit(RepostCreateEvent {
            delegate: delegate_address,
            kid,
            refference_kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun remove_repost(delegate: &signer, kid: u256) {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);

        event::emit(RepostRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun create_quote(delegate: &signer, reference_kid: u256, payload: string::String) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.quoute_count;
        state.quoute_count = state.quoute_count + 1;

        event::emit(QuoteCreateEvent {
            delegate: delegate_address,
            kid,
            reference_kid,
            timestamp: timestamp::now_seconds(),
            user_kid,
            payload
        })
    }

    public entry fun remove_quote(delegate: &signer, kid: u256) {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);

        event::emit(QuoteRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun create_reaction(delegate: &signer, reaction: u64) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.reaction_count;
        state.reaction_count = state.reaction_count + 1;

        event::emit(ReactionCreateEvent {
            delegate: delegate_address,
            kid,
            reaction,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }

    public entry fun remove_reaction(delegate: &signer, kid: u256) {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);

        event::emit(ReactionRemoveEvent {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        })
    }



    // ====
    // Tests
    // ====

    #[test(admin = @kade)]
    fun test_init_module(admin: &signer) acquires  State {

        init_module(admin);

        let resource_address = account::create_resource_address(&@kade, SEED);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 1,1);

        let events = emitted_events<PublicationCreate>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.payload == string::utf8(b"Hello World"),4);

        assert!(event.user_kid == 0,5);


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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 1,1);

        let events = emitted_events<PublicationCreate>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.payload == string::utf8(b"Hello World"),4);

        assert!(event.user_kid == 0,5);

        remove_publication(&delegate, 0);

        let events = emitted_events<PublicationRemove>();

        assert!(vector::length(&events) == 1,6);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,7);

        assert!(event.user_kid == 0,8);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_comment(&delegate, 0, 1);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.comment_count == 1,1);

        let events = emitted_events<CommentCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.refference_kid == 0,4);

        assert!(event.user_kid == 0,5);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_comment(&delegate, 0, 1);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.comment_count == 1,1);

        let events = emitted_events<CommentCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.refference_kid == 0,4);

        assert!(event.user_kid == 0,5);

        remove_comment(&delegate, 0);

        let events = emitted_events<CommentDeleteEvent>();

        assert!(vector::length(&events) == 1,6);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,7);

        assert!(event.user_kid == 0,8);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_repost(&delegate, 0);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.repost_count == 1,1);

        let events = emitted_events<RepostCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.refference_kid == 0,4);

        assert!(event.user_kid == 0,5);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_repost(&delegate, 0);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.repost_count == 1,1);

        let events = emitted_events<RepostCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.refference_kid == 0,4);

        assert!(event.user_kid == 0,5);

        remove_repost(&delegate, 0);

        let events = emitted_events<RepostRemoveEvent>();

        assert!(vector::length(&events) == 1,6);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,7);

        assert!(event.user_kid == 0,8);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_quote(&delegate, 0, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.quoute_count == 1,1);

        let events = emitted_events<QuoteCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.reference_kid == 0,4);

        assert!(event.user_kid == 0,5);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_quote(&delegate, 0, string::utf8(b"Hello World"));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.quoute_count == 1,1);

        let events = emitted_events<QuoteCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.reference_kid == 0,4);

        assert!(event.user_kid == 0,5);

        remove_quote(&delegate, 0);

        let events = emitted_events<QuoteRemoveEvent>();

        assert!(vector::length(&events) == 1,6);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,7);

        assert!(event.user_kid == 0,8);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_reaction(&delegate, 1);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.reaction_count == 1,1);

        let events = emitted_events<ReactionCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.reaction == 1,4);

        assert!(event.user_kid == 0,5);

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
        init_module(admin);
        accounts::create_account(&user, string::utf8(b"kade"));

        accounts::add_account_delegate(&user, &delegate);

        create_publication(&delegate, string::utf8(b"Hello World"));

        create_reaction(&delegate, 1);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.reaction_count == 1,1);

        let events = emitted_events<ReactionCreateEvent>();

        assert!(vector::length(&events) == 1,2);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,3);

        assert!(event.reaction == 1,4);

        assert!(event.user_kid == 0,5);

        remove_reaction(&delegate, 0);

        let events = emitted_events<ReactionRemoveEvent>();

        assert!(vector::length(&events) == 1,6);

        let event = vector::borrow(&events, 0);

        assert!(event.kid == 0,7);

        assert!(event.user_kid == 0,8);

    }










}
