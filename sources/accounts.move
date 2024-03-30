
/**
    * This module contains logic for managing users in the account registry and delegates that users add to their accounts
**/

module kade::accounts {
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::string_utils;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use kade::usernames;
    #[test_only]
    use std::features;
    #[test_only]
    use aptos_std::debug;

    friend kade::publications;


    // ===
    // Error Codes
    // ===
    const EDelegateDoesNotExist:u64 = 20;
    const EUsernameNotRegistered: u64 = 21;
    const EUsernameNotOwned: u64 = 22;
    const EOperationNotPermitted: u64 = 23;
    const EDoesNotExists: u64 = 24;

    const SEED: vector<u8> = b"kade::accountsv1";

    struct LocalAccountReferences has key {
        transfer_ref: object::TransferRef,
        delete_ref: object::DeleteRef,
        object_address: address,
        last_delegate_link_intent: option::Option<address>,
        username: string::String, // transfering and deletion will be implemented in v2
    }

    struct KadeAccount has key, copy, drop {
        delegates: vector<address>,
        kid: u64,
        publication_kid_count: u64,
        follow_kid_count: u64
    }

    struct DelegateAccount has key, drop {
        owner: address,
        account_object_address: address,
        kid: u64,
    }

    struct State has key {
        registry_count: u64,
        relations_count: u64,
        delegates_count: u64,
        signer_capability: account::SignerCapability,
        account_creation_events: event::EventHandle<AccountCreateEvent>,
        delegate_creation_events: event::EventHandle<DelegateCreateEvent>,
        delegate_remove_events: event::EventHandle<DelegateRemoveEvent>,
        account_follow_events: event::EventHandle<AccountFollowEvent>,
        account_unfollow_events: event::EventHandle<AccountUnFollowEvent>,
        profile_update_events: event::EventHandle<ProfileUpdateEvent>,
    }

    #[event]
    struct AccountCreateEvent has store, drop {
        username: string::String,
        creator_address: address,
        account_object_address: address,
        kid: u64,
        timestamp: u64,
    }

    #[event]
    struct DelegateCreateEvent has store, drop {
        owner_address: address,
        object_address: address,
        delegate_address: address,
        kid: u64,
        timestamp: u64,
    }

    #[event]
    struct DelegateRemoveEvent has store, drop {
        owner_address: address,
        object_address: address,
        delegate_address: address,
        kid: u64,
        timestamp: u64,
    }

    #[event]
    struct AccountFollowEvent has store, drop {
        follower_kid: u64,
        following_kid: u64,
        follower: address,
        following: address,
        kid: u64,
        delegate: address,
        user_kid: u64,
        timestamp: u64,
    }


    #[event]
    struct AccountUnFollowEvent has store, drop {
        delegate: address,
        user_kid: u64,
        timestamp: u64,
        unfollowing_kid: u64,
    }

    #[event]
    struct ProfileUpdateEvent has store, drop {
        user_kid: u64,
        delegate: address,
        timestamp: u64,
        pfp: string::String,
        bio: string::String,
        display_name: string::String,
    }

    fun init_module(admin: &signer) {
        let (resource_signer, signer_capability) = account::create_resource_account(admin, SEED);

        move_to(&resource_signer, State {
            registry_count: 100, // reserve 0-99 for error codes and possible system accounts
            signer_capability,
            relations_count: 100, // reserve 0-99 for error codes and possible system accounts
            delegates_count: 100, // reserve 0-99 for error codes and possible system accounts
            account_creation_events: account::new_event_handle(&resource_signer),
            delegate_creation_events: account::new_event_handle(&resource_signer),
            delegate_remove_events: account::new_event_handle(&resource_signer),
            account_follow_events: account::new_event_handle(&resource_signer),
            account_unfollow_events: account::new_event_handle(&resource_signer),
            profile_update_events: account::new_event_handle(&resource_signer),
        })
    }



    public entry fun create_account(user: &signer, username: string::String)acquires State {

        let username_exists = usernames::is_username_claimed(username);
        assert!(username_exists, EUsernameNotRegistered);

        let owns_username = usernames::is_address_username_owner(signer::address_of(user), username);
        assert!(owns_username, EUsernameNotOwned);

        let user_address = signer::address_of(user);
        assert!(!exists<LocalAccountReferences>(user_address), 1);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        let constructor_ref = object::create_object(user_address);

        let transfer_ref = object::generate_transfer_ref(&constructor_ref);
        let delete_ref = object::generate_delete_ref(&constructor_ref);
        let object_signer = object::generate_signer(&constructor_ref);
        let object_address = object::address_from_constructor_ref(&constructor_ref);

        let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);

        object::transfer_with_ref(linear_transfer_ref, user_address);

        move_to(user, LocalAccountReferences {
            transfer_ref,
            delete_ref,
            object_address,
            last_delegate_link_intent: option::none(),
            username
        });

        let new_account = KadeAccount {
            delegates: vector::empty(),
            kid: state.registry_count,
            follow_kid_count: 0,
            publication_kid_count: 0
        };

        move_to(&object_signer, new_account);

        state.registry_count = state.registry_count + 1;

        event::emit_event(&mut state.account_creation_events, AccountCreateEvent {
            username,
            creator_address: user_address,
            account_object_address: object_address,
            kid: new_account.kid,
            timestamp: timestamp::now_seconds(),
        })
    }

    // DEFER GAS FEES to kade
    public entry fun gd_create_account(admin: &signer, user: &signer, username: string::String) acquires State  {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        create_account(user, username);
    }

    public entry fun add_account_delegate(user: &signer, delegate: &signer) acquires  LocalAccountReferences, KadeAccount, State {

        let user_address = signer::address_of(user);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state  = borrow_global_mut<State>(resource_address);
        let localAccountRefData = borrow_global<LocalAccountReferences>(user_address);
        let object_address = localAccountRefData.object_address;

        let kade_account = borrow_global_mut<KadeAccount>(object_address);

        let delegate_address = signer::address_of(delegate);

        vector::push_back(&mut kade_account.delegates, delegate_address);
        let delegate_kid = state.delegates_count;
        let delegate_data = DelegateAccount {
            owner: user_address,
            account_object_address: localAccountRefData.object_address,
            kid: delegate_kid,
        };

        move_to<DelegateAccount>(delegate,delegate_data );

        state.delegates_count = state.delegates_count + 1;

        event::emit_event(&mut state.delegate_creation_events, DelegateCreateEvent {
            delegate_address,
            object_address,
            owner_address: user_address,
            kid: delegate_kid,
            timestamp: timestamp::now_seconds(),
        })
    }

    public entry fun delegate_link_intent(user: &signer, delegate: address) acquires LocalAccountReferences {
        let user_address = signer::address_of(user);
        let local_account_ref = borrow_global_mut<LocalAccountReferences>(user_address);
        local_account_ref.last_delegate_link_intent = option::some(delegate);
    }

    public entry fun account_link_intent(delegate: &signer, user_address: address) acquires LocalAccountReferences, State, KadeAccount {
        let account = borrow_global_mut<LocalAccountReferences>(user_address);
        assert!(option::is_some(&account.last_delegate_link_intent), EOperationNotPermitted);
        let intended_delegate = *option::borrow(&account.last_delegate_link_intent);
        assert!(intended_delegate == signer::address_of(delegate), EOperationNotPermitted);
        account.last_delegate_link_intent = option::none();

        let resource_address = account::create_resource_address(&@kade, SEED);
        let state  = borrow_global_mut<State>(resource_address);
        let object_address = account.object_address;

        let kade_account = borrow_global_mut<KadeAccount>(object_address);

        let delegate_address = signer::address_of(delegate);

        vector::push_back(&mut kade_account.delegates, delegate_address);
        let delegate_kid = state.delegates_count;
        let delegate_data = DelegateAccount {
            owner: user_address,
            account_object_address: account.object_address,
            kid: delegate_kid,
        };

        move_to<DelegateAccount>(delegate,delegate_data );

        state.delegates_count = state.delegates_count + 1;

        event::emit_event(&mut state.delegate_creation_events, DelegateCreateEvent {
            delegate_address,
            object_address,
            owner_address: user_address,
            kid: delegate_kid,
            timestamp: timestamp::now_seconds(),
        })

    }

    public entry fun create_account_and_add_delegate(user: &signer, delegate: &signer, username: string::String) acquires LocalAccountReferences, KadeAccount, State {
        create_account(user, username);
        add_account_delegate(user, delegate);
    }

    public entry fun create_account_and_delegate_link_intent(user: &signer, delegate: address, username: string::String) acquires LocalAccountReferences, State {
        create_account(user, username);
        delegate_link_intent(user, delegate);
    }

    public entry fun gd_account_setup_with_self_delegate(admin: &signer, user: &signer, username: string::String) acquires LocalAccountReferences, State, KadeAccount {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        usernames::claim_username(user, username);
        create_account(user, username);
        delegate_link_intent(user, signer::address_of(user));
        account_link_intent(user, signer::address_of(user));
    }

    public entry fun account_setup_with_self_delegate(user: &signer, username: string::String) acquires LocalAccountReferences, State, KadeAccount {
        usernames::claim_username(user, username);
        create_account(user, username);
        delegate_link_intent(user, signer::address_of(user));
        account_link_intent(user, signer::address_of(user));
    }

    // DEFER GAS FEES to kade
    public entry fun gd_add_account_delegate(admin: &signer, user: &signer, delegate: &signer) acquires LocalAccountReferences, KadeAccount, State {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermitted);
        add_account_delegate(user, delegate);
    }

    public entry fun remove_account_delegate(user: &signer, delegate_address: address) acquires LocalAccountReferences, KadeAccount, DelegateAccount, State {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        let user_address = signer::address_of(user);
        let local = borrow_global<LocalAccountReferences>(user_address);
        let account_object = borrow_global_mut<KadeAccount>(local.object_address);

        assert!(vector::contains(&account_object.delegates, &delegate_address), EDelegateDoesNotExist);

        let delegate_data = move_from<DelegateAccount>(delegate_address);

        vector::remove_value(&mut account_object.delegates, &delegate_address);

        event::emit_event(&mut state.delegate_remove_events, DelegateRemoveEvent {
            delegate_address,
            object_address: local.object_address,
            owner_address: user_address,
            kid: delegate_data.kid,
            timestamp: timestamp::now_seconds(),
        })
    }

    public entry fun update_profile(delegate: &signer, pfp: string::String, bio: string::String, display_name: string::String) acquires KadeAccount, State, DelegateAccount {
        let resource_address  =account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);
        let user_kid = get_delegate_owner(delegate);


        event::emit_event(&mut state.profile_update_events, ProfileUpdateEvent {
            delegate: signer::address_of(delegate),
            user_kid,
            timestamp: timestamp::now_seconds(),
            pfp,
            bio,
            display_name,
        })
    }


    // TODO: transfer account
    // TODO: delete account

    public entry fun follow_account(delegate: &signer, following_address: address) acquires KadeAccount,State, DelegateAccount, LocalAccountReferences {
        let resource_address  =account::create_resource_address(&@kade, SEED);
        let delegate_address = signer::address_of(delegate);

        let state = borrow_global_mut<State>(resource_address);

        let kid = state.relations_count;
        state.relations_count = state.relations_count + 1;

        let delegate = borrow_global<DelegateAccount>(delegate_address);
        let localAccountData = borrow_global<LocalAccountReferences>(following_address);

        let follower = get_account_owner(delegate.account_object_address);
        let following = get_account_owner(localAccountData.object_address);
        increment_follow_kid(delegate.account_object_address);

        event::emit_event(&mut state.account_follow_events, AccountFollowEvent {
            follower_kid: follower.kid,
            following_kid: following.kid,
            follower: delegate.owner,
            following: following_address,
            kid,
            delegate: delegate_address,
            user_kid: follower.kid,
            timestamp: timestamp::now_seconds(),
        })

    }

    public entry fun unfollow_account(delegate: &signer, unfollowing_address: address)acquires DelegateAccount, KadeAccount, State, LocalAccountReferences {

        let delegate_address = signer::address_of(delegate);
        let user_kid = get_delegate_owner(delegate);
        let unfollowing_account_ref = borrow_global<LocalAccountReferences>(unfollowing_address);
        let unfollowing_kid = get_account_owner(unfollowing_account_ref.object_address).kid;

        let resource_address  =account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        event::emit_event(&mut state.account_unfollow_events, AccountUnFollowEvent {
            delegate: delegate_address,
            user_kid,
             unfollowing_kid,
            timestamp: timestamp::now_seconds(),
        })
    }


    public(friend) fun get_delegate_owner(delegate: &signer): u64 acquires DelegateAccount, KadeAccount {
        let delegate_address = signer::address_of(delegate);
        assert!(exists<DelegateAccount>(delegate_address), EDelegateDoesNotExist);

        let data = borrow_global<DelegateAccount>(delegate_address);

        let account_data = borrow_global<KadeAccount>(data.account_object_address);

        account_data.kid



    }


    public (friend) fun get_delegate_owner_address(delegate: &signer): address acquires DelegateAccount {
        let delegate_address = signer::address_of(delegate);
        assert!(exists<DelegateAccount>(delegate_address), EDelegateDoesNotExist);

        let data = borrow_global<DelegateAccount>(delegate_address);

        data.owner
    }

    public(friend) fun get_account_owner(account_address: address): KadeAccount acquires KadeAccount {
        let account_data = *borrow_global<KadeAccount>(account_address);
        account_data
    }

    inline fun increment_follow_kid(account_address: address) acquires KadeAccount {
        let account_data = borrow_global_mut<KadeAccount>(account_address);
        account_data.follow_kid_count = account_data.follow_kid_count + 1;
    }

    public(friend) fun increment_publication_kid(user: address) acquires KadeAccount, LocalAccountReferences {
        let local =  borrow_global<LocalAccountReferences>(user);
        let account_data = borrow_global_mut<KadeAccount>(local.object_address);
        account_data.publication_kid_count = account_data.publication_kid_count + 1
    }

    public(friend) fun get_publication_ref(user: address): string::String acquires KadeAccount, LocalAccountReferences {
        let local = borrow_global<LocalAccountReferences>(user);
        let account_data = borrow_global<KadeAccount>(local.object_address);
        let username = local.username;
        let ref = string_utils::format2(&b"publication:{}:{}",username, account_data.publication_kid_count );
        return ref
    }

    #[view]
    public fun get_account(account_address: address): (u64, vector<address>) acquires KadeAccount, LocalAccountReferences {

        if(!exists<LocalAccountReferences>(account_address)){
             return (0, vector::empty<address>())
        };
        let ref = borrow_global<LocalAccountReferences>(account_address);
        if(!exists<KadeAccount>(ref.object_address)){
            return (0, vector::empty<address>())
        };
        let account_data = borrow_global<KadeAccount>(ref.object_address);
        (account_data.kid, account_data.delegates)
    }

    #[view]
    public fun delegate_get_owner(delegate_address: address): (u64, address) acquires DelegateAccount, KadeAccount {
        if(!exists<DelegateAccount>(delegate_address)){
            return (0, @0x0)
        };
        let data = borrow_global<DelegateAccount>(delegate_address);
        let account_data = borrow_global<KadeAccount>(data.account_object_address);
        (account_data.kid, data.owner)
    }

    #[view]
    public fun get_current_username(user: address): string::String acquires LocalAccountReferences {
        let local = borrow_global<LocalAccountReferences>(user);
        let username = local.username;
        return username
    }

    // TODO: get the account local object
    // TODO: get the account KadeAccount object

    #[test_only]
    public(friend)  fun invoke_init_module(admin: &signer) {
        init_module(admin);


    }

    #[test_only]
    public fun dependancy_test_init_module(test_admin: &signer) {
        init_module(test_admin);
    }


    // =========
    // TESTS
    // =========
    #[test(admin = @kade)]
    fun test_init_module(admin: &signer) acquires State {
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x1);

        init_module(admin);

        let expeected_resource_address = account::create_resource_address(&@kade, SEED);

        debug::print(&expeected_resource_address);

        let state = borrow_global<State>(expeected_resource_address);

        assert!(state.registry_count == 100, 1);


    }

    #[test(admin = @kade, user = @0x23)]
    fun test_create_account_success(admin: &signer, user: &signer) acquires State, LocalAccountReferences, KadeAccount {
        let aptos_framework = account::create_account_for_test(@0x1);
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x233);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);


        init_module(admin);
        let username = string::utf8(b"kade");
        usernames::invoke_init_module(admin);
        usernames::claim_username(user, username);
        create_account(user, username);

        let resource_address = account::create_resource_address(&@kade, SEED);
        let state = borrow_global<State>(resource_address);

        assert!(event::counter(&state.account_creation_events) == 1, 1);

        let local_account_ref = borrow_global<LocalAccountReferences>(signer::address_of(user));

        let account = borrow_global<KadeAccount>(local_account_ref.object_address);

        assert!(account.kid == 100, 4);

        assert!(vector::length(&account.delegates) == 0, 5);

    }

    #[test(admin = @kade, user = @0x23, delegate = @0x24)]
    fun test_add_account_delegate_success(admin: &signer, user: &signer, delegate: &signer) acquires State, LocalAccountReferences, KadeAccount, DelegateAccount {
        let aptos_framework = account::create_account_for_test(@0x1);
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x233);
        account::create_account_for_test(@0x234);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        init_module(admin);
        let username = string::utf8(b"kade");
        usernames::invoke_init_module(admin);
        usernames::claim_username(user, username);
        create_account(user, username);

        add_account_delegate(user, delegate);

        let local_account_ref = borrow_global<LocalAccountReferences>(signer::address_of(user));

        let account = borrow_global<KadeAccount>(local_account_ref.object_address);

        let delegate_address = signer::address_of(delegate);

        assert!(vector::length(&account.delegates) == 1, 1);

        assert!(vector::contains(&account.delegates, &delegate_address), 2);

        let delegate_account = borrow_global<DelegateAccount>(delegate_address);

        assert!(delegate_account.owner == signer::address_of(user), 3);

        assert!(delegate_account.account_object_address == local_account_ref.object_address, 4);

    }

    #[test(admin = @kade, user = @0x23, delegate = @0x24)]
    fun test_remove_account_delegate_success(admin: &signer, user: &signer, delegate: &signer) acquires State, LocalAccountReferences, KadeAccount, DelegateAccount {
        let aptos_framework = account::create_account_for_test(@0x1);
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x233);
        account::create_account_for_test(@0x234);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        init_module(admin);
        usernames::invoke_init_module(admin);
        let username = string::utf8(b"kade");
        usernames::claim_username(user, username);
        create_account(user, username);

        add_account_delegate(user, delegate);

        remove_account_delegate(user, signer::address_of(delegate));

        let local_account_ref = borrow_global<LocalAccountReferences>(signer::address_of(user));

        let account = borrow_global<KadeAccount>(local_account_ref.object_address);

        let delegate_address = signer::address_of(delegate);

        assert!(vector::length(&account.delegates) == 0, 1);

        assert!(!vector::contains(&account.delegates, &delegate_address), 2);

        assert!(!exists<DelegateAccount>(delegate_address), 3);

    }

    #[test(admin = @kade, user1 = @0x23, user2 = @0x45, delegate = @0x24)]
    fun test_follow_account_success(admin: &signer, user1: &signer, user2: &signer, delegate: &signer) acquires State, LocalAccountReferences, KadeAccount, DelegateAccount {
        let aptos_framework = account::create_account_for_test(@0x1);
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x233);
        account::create_account_for_test(@0x234);
        account::create_account_for_test(@0x235);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        init_module(admin);
        usernames::invoke_init_module(admin);
        let username = string::utf8(b"kade");
        let username_2 = string::utf8(b"kade2");
        usernames::claim_username(user1, username);
        create_account(user1, username);
        usernames::claim_username(user2, username_2);
        create_account(user2, username_2);

        add_account_delegate(user1, delegate);

        follow_account(delegate, signer::address_of(user2));

        let resource_address  =account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        assert!(event::counter(&state.account_follow_events) == 1, 1);



    }

    #[test(admin = @kade, user1 = @0x23, user2 = @0x45, delegate = @0x24)]
    fun test_unfollow_account_success(admin: &signer, user1: &signer, user2: &signer, delegate: &signer) acquires State, LocalAccountReferences, KadeAccount, DelegateAccount {
        let aptos_framework = account::create_account_for_test(@0x1);
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x233);
        account::create_account_for_test(@0x234);
        account::create_account_for_test(@0x235);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        init_module(admin);
        usernames::invoke_init_module(admin);
        let username = string::utf8(b"kade");
        let username_2 = string::utf8(b"kade2");
        usernames::claim_username(user1, username);
        create_account(user1, username);
        usernames::claim_username(user2, username_2);
        create_account(user2, username_2);

        add_account_delegate(user1, delegate);

        follow_account(delegate, signer::address_of(user2));

        unfollow_account(delegate, signer::address_of(user2));

        let resource_address  =account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        assert!(event::counter(&state.account_unfollow_events) == 1, 1);

    }

    #[test(admin = @kade, user = @0x23, delegate = @0x24)]
    fun test_update_profile_success(admin: &signer, user: &signer, delegate: &signer) acquires State, LocalAccountReferences, KadeAccount, DelegateAccount {
        let aptos_framework = account::create_account_for_test(@0x1);
        account::create_account_for_test(@kade);
        account::create_account_for_test(@0x233);
        account::create_account_for_test(@0x234);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        init_module(admin);
        usernames::invoke_init_module(admin);
        let username = string::utf8(b"kade");
        usernames::claim_username(user, username);
        create_account(user, username);

        add_account_delegate(user, delegate);

        update_profile(delegate, string::utf8(b"pfp"), string::utf8(b"bio"), string::utf8(b"display_name"));

        let resource_address  =account::create_resource_address(&@kade, SEED);
        let state = borrow_global_mut<State>(resource_address);

        assert!(event::counter(&state.profile_update_events) == 1, 1);

    }

    #[test]
    fun test_test_delegate_link_intent() acquires State, LocalAccountReferences, KadeAccount {
        let kade = account::create_account_for_test(@kade);
        let aptos_framework = account::create_account_for_test(@0x1);
        let delegate = account::create_account_for_test(@0x2);

        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(&kade);
        usernames::invoke_init_module(&kade);
        let username = string::utf8(b"kade");
        usernames::claim_username(&kade, username);
        create_account(&kade, username);

        delegate_link_intent(&kade, signer::address_of(&delegate));
        account_link_intent(&delegate, signer::address_of(&kade));


    }

    #[test]
    #[expected_failure(abort_code = EOperationNotPermitted)]
    fun test_delegate_link_intent_failure() acquires State, LocalAccountReferences, KadeAccount {
        let kade = account::create_account_for_test(@kade);
        let aptos_framework = account::create_account_for_test(@0x1);
        let delegate = account::create_account_for_test(@0x2);
        let delegate2 = account::create_account_for_test(@0x3);

        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);

        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(&kade);
        usernames::invoke_init_module(&kade);
        let username = string::utf8(b"kade");
        usernames::claim_username(&kade, username);
        create_account(&kade, username);

        delegate_link_intent(&kade, signer::address_of(&delegate));
        account_link_intent(&delegate2, signer::address_of(&kade));
    }

    #[test]
    fun test_create_account_and_delegate_link_intent() acquires State, LocalAccountReferences {
        let kade = account::create_account_for_test(@kade);
        let aptos_framework = account::create_account_for_test(@0x1);
        let delegate = account::create_account_for_test(@0x2);

        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(&kade);
        usernames::invoke_init_module(&kade);
        let username = string::utf8(b"kade");
        usernames::claim_username(&kade, username);
        create_account_and_delegate_link_intent(&kade, signer::address_of(&delegate), username);

    }


    #[test]
    fun test_account_setup_with_self_delegate() acquires State, LocalAccountReferences, KadeAccount {
        let kade = account::create_account_for_test(@kade);
        let aptos_framework = account::create_account_for_test(@0x1);

        let feature = features::get_module_event_feature();
        features::change_feature_flags(&aptos_framework, vector[feature], vector[]);
        timestamp::set_time_has_started_for_testing(&aptos_framework);

        init_module(&kade);
        usernames::invoke_init_module(&kade);
        let username = string::utf8(b"kade");
        gd_account_setup_with_self_delegate(&kade,&kade, username);
    }



}
