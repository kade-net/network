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

    const SEED: vector<u8> = b"kade::publicationsv1";

    const EOperationNotPermitted: u64 = 101;

    struct State has key {
        publication_count: u64,
        reaction_count: u64,
        signer_capability:  account::SignerCapability,
        publication_create_events: event::EventHandle<PublicationCreate>,
        publication_create_with_ref_events: event::EventHandle<PublicationCreateWithRef>,
        publication_remove_events: event::EventHandle<PublicationRemove>,
        publication_remove_with_ref_events: event::EventHandle<PublicationRemoveWithRef>,
        reaction_create_events: event::EventHandle<ReactionCreateEvent>,
        reaction_create_with_ref_events: event::EventHandle<ReactionCreateEventWithRef>,
        reaction_remove_events: event::EventHandle<ReactionRemoveEvent>,
        reaction_remove_with_ref_events: event::EventHandle<ReactionRemoveEventWithRef>,
    }


    #[event]
    struct PublicationCreate has store, drop {
        kid: u64,
        payload: string::String,  // stringified json payload
        user_kid: u64,
        delegate: address,
        timestamp: u64,
        type: u64, // 1 for post, 2 for quotes , 3 for comments, 4 for reposts
        reference_kid: u64, // should always reference a kid lower than the current kid
        publication_ref: string::String
    }

    #[event]
    struct PublicationCreateWithRef has store, drop { // This is only for interactions that have a reference to another publication
        kid: u64,
        payload: string::String,  // stringified json payload
        user_kid: u64,
        delegate: address,
        timestamp: u64,
        type: u64, // 1 for post, 2 for quotes , 3 for comments, 4 for reposts
        publication_ref: string::String,
        parent_ref: string::String // to make it easier for off chain clients to work with an offline first approach
    }

    #[event]
    struct  PublicationRemove has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64
    }

    #[event]
    struct PublicationRemoveWithRef has store, drop {
        user_kid: u64,
        delegate: address,
        timestamp: u64,
        ref: string::String
    }


    #[event]
    struct ReactionCreateEvent has store, drop {
        kid: u64,
        reference_kid: u64,
        user_kid: u64,
        delegate: address,
        reaction: u64,
        timestamp: u64,
    }

    #[event]
    struct ReactionCreateEventWithRef has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        reaction: u64,
        timestamp: u64,
        publication_ref: string::String
    }

    #[event]
    struct ReactionRemoveEvent has store, drop {
        kid: u64,
        user_kid: u64,
        delegate: address,
        timestamp: u64,
    }

    #[event]
    struct ReactionRemoveEventWithRef has store, drop {
        user_kid: u64,
        delegate: address,
        timestamp: u64,
        ref: string::String
    }


    fun init_module(admin: &signer) {
        let (resource_signer, signer_capability ) = account::create_resource_account(admin, SEED);

        move_to(&resource_signer, State {
            signer_capability,
            reaction_count: 100, // the first 100(0-99) kids are reserved for error codes
            publication_count: 100, // the first 100(0-99) kids are reserved for error codes
            publication_create_events: account::new_event_handle(&resource_signer),
            publication_remove_events: account::new_event_handle(&resource_signer),
            publication_create_with_ref_events: account::new_event_handle(&resource_signer),
            publication_remove_with_ref_events: account::new_event_handle(&resource_signer),
            reaction_create_events: account::new_event_handle(&resource_signer),
            reaction_create_with_ref_events: account::new_event_handle(&resource_signer),
            reaction_remove_events: account::new_event_handle(&resource_signer),
            reaction_remove_with_ref_events: account::new_event_handle(&resource_signer),
        });

    }


    public entry fun create_publication(delegate: &signer, type: u64, payload: string::String, reference_kid: u64, ref: string::String) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.publication_count;
        assert!(reference_kid < kid, 101);
        state.publication_count = state.publication_count + 1;


        let owner_address = accounts::get_delegate_owner_address(delegate);
        let current_pub_ref = accounts::get_publication_ref(owner_address);
        accounts::increment_publication_kid(owner_address);

        let publication_ref = ref;
        if(string::length(&ref) == 0){
            publication_ref = current_pub_ref;
        };

        event::emit_event(&mut state.publication_create_events, PublicationCreate {
            delegate: delegate_address,
            kid,
            payload,
            timestamp: timestamp::now_seconds(),
            user_kid,
            type,
            reference_kid, // 0 means no reference
            publication_ref
        });
    }

    public entry fun create_publication_with_ref(delegate: &signer, type: u64, payload: string::String, ref: string::String, parent_ref: string::String) acquires State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.publication_count;
        state.publication_count = state.publication_count + 1;
        assert!(string::length(&ref) > 0, 101);
        let owner_address = accounts::get_delegate_owner_address(delegate);
        let current_pub_ref = accounts::get_publication_ref(owner_address);
        accounts::increment_publication_kid(owner_address);

        let publication_ref = ref;
        if(string::length(&ref) == 0){
            publication_ref = current_pub_ref;
        };

        event::emit_event(&mut state.publication_create_with_ref_events, PublicationCreateWithRef {
            delegate: delegate_address,
            kid,
            payload,
            timestamp: timestamp::now_seconds(),
            user_kid,
            type,
            publication_ref,
            parent_ref
        });
    }



    public entry fun remove_publication(delegate: &signer, kid: u64) acquires State {
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        assert!(kid < state.publication_count, 101);

        event::emit_event(&mut state.publication_remove_events, PublicationRemove {
            delegate: delegate_address,
            kid,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    public entry fun remove_publication_with_ref(delegate: &signer, ref: string::String) acquires State {
        assert!(string::length(&ref) > 0, 101);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);


        event::emit_event(&mut state.publication_remove_with_ref_events, PublicationRemoveWithRef {
            delegate: delegate_address,
            ref,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    public entry fun create_reaction(delegate: &signer, reaction: u64, reference_kid: u64) acquires State {
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
            reference_kid
        });
    }

    public entry fun create_reaction_with_ref(delegate: &signer, reaction: u64, ref: string::String) acquires State {
        assert!(string::length(&ref) > 0, 101);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let state = borrow_global_mut<State>(resource_address);
        let kid = state.reaction_count;
        state.reaction_count = state.reaction_count + 1;

        event::emit_event(&mut state.reaction_create_with_ref_events, ReactionCreateEventWithRef {
            delegate: delegate_address,
            reaction,
            timestamp: timestamp::now_seconds(),
            user_kid,
            publication_ref: ref,
            kid
        });
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

    public entry fun remove_reaction_with_ref(delegate: &signer, ref: string::String) acquires State {
        assert!(string::length(&ref) > 0, 101);
        let delegate_address = signer::address_of(delegate);
        let user_kid = accounts::get_delegate_owner(delegate);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.reaction_remove_with_ref_events, ReactionRemoveEventWithRef {
            delegate: delegate_address,
            ref,
            timestamp: timestamp::now_seconds(),
            user_kid
        });
    }

    #[test_only]
    public fun dependancy_test_init_module(test_admin: &signer) {
        init_module(test_admin);
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

        assert!(state.publication_count == 100,1);
        assert!(state.reaction_count == 100,2);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 101,1);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));

        remove_publication(&delegate, 0);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 101,1);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));
        create_publication(&delegate, 3, string::utf8(b"Hello World"), 100, string::utf8(b""));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 102,1);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));

        create_publication(&delegate, 3, string::utf8(b"Hello World"), 100, string::utf8(b""));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 102,1);

        remove_publication(&delegate, 101);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));

        create_publication(&delegate, 4, string::utf8(b"Hello World"), 100, string::utf8(b""));

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.publication_count == 102,1);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));

        create_reaction(&delegate, 1, 100);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.reaction_count == 101,1);

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

        create_publication(&delegate, 1, string::utf8(b"Hello World"), 0, string::utf8(b""));

        create_reaction(&delegate, 1, 100);

        remove_reaction(&delegate, 100);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let state = borrow_global<State>(expected_resource_address);

        assert!(state.reaction_count == 101,1);

    }










}
