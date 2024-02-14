
/**
    * This module contains logic for managing users in the account registry and delegates that users add to their accounts
**/

module kade::accounts {
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::object;
    #[test_only]
    use std::features;
    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use aptos_framework::event::emitted_events;
    #[test_only]
    use aptos_framework::timestamp;

    friend kade::publications;


    // ===
    // Error Codes
    // ===
    const EDelegateDoesNotExist:u64 = 20;

    const SEED: vector<u8> = b"kade::accountsv1.0.0";

    struct LocalAccountReferences has key {
        transfer_ref: object::TransferRef,
        delete_ref: object::DeleteRef,
        object_address: address,
    }

    struct KadeAccount has key, copy, drop {
        username: string::String,
        delegates: vector<address>,
        kid: u64
    }

    struct DelegateAccount has key, drop {
        owner: address,
        account_object_address: address,
    }

    struct State has key {
        registry_count: u64,
        relations_count: u64,
        signer_capability: account::SignerCapability,
    }

    #[event]
    struct AccountCreateEvent has store, drop {
        username: string::String,
        creator_address: address,
        account_object_address: address,
        kid: u64,
    }

    #[event]
    struct DelegateCreateEvent has store, drop {
        owner_address: address,
        object_address: address,
        delegate_address: address,
    }

    #[event]
    struct DelegateRemoveEvent has store, drop {
        owner_address: address,
        object_address: address,
        delegate_address: address,
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
    }


    #[event]
    struct AccountUnFollowEvent has store, drop {
        delegate: address,
        user_kid: u64,
        kid: u64,
    }

    fun init_module(admin: &signer) {
        let (resource_signer, signer_capability) = account::create_resource_account(admin, SEED);

        move_to(&resource_signer, State {
            registry_count: 0,
            signer_capability,
            relations_count: 0,
        })
    }



    public entry fun create_account(user: &signer, username: string::String)acquires State {

        let user_address = signer::address_of(user);
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
            object_address
        });

        let new_account = KadeAccount {
            username,
            delegates: vector::empty(),
            kid: state.registry_count,
        };

        move_to(&object_signer, new_account);

        state.registry_count = state.registry_count + 1;



        event::emit(AccountCreateEvent {
            username,
            creator_address: user_address,
            account_object_address: object_address,
            kid: new_account.kid,
        })
    }

    public entry fun add_account_delegate(user: &signer, delegate: &signer) acquires  LocalAccountReferences, KadeAccount {

        let user_address = signer::address_of(user);

        let localAccountRefData = borrow_global<LocalAccountReferences>(user_address);
        let object_address = localAccountRefData.object_address;

        let kade_account = borrow_global_mut<KadeAccount>(object_address);

        let delegate_address = signer::address_of(delegate);

        vector::push_back(&mut kade_account.delegates, delegate_address);

        move_to<DelegateAccount>(delegate, DelegateAccount {
            owner: user_address,
            account_object_address: localAccountRefData.object_address
        });

        event::emit(DelegateCreateEvent {
            delegate_address,
            object_address,
            owner_address: user_address,
        })
    }


    public entry fun remove_account_delegate(user: &signer, delegate_address: address) acquires LocalAccountReferences, KadeAccount, DelegateAccount {
        let user_address = signer::address_of(user);
        let local = borrow_global<LocalAccountReferences>(user_address);
        let account_object = borrow_global_mut<KadeAccount>(local.object_address);

        assert!(vector::contains(&account_object.delegates, &delegate_address), EDelegateDoesNotExist);

        move_from<DelegateAccount>(delegate_address);

        vector::remove_value(&mut account_object.delegates, &delegate_address);

        event::emit(DelegateRemoveEvent {
            delegate_address,
            object_address: local.object_address,
            owner_address: user_address,
        })
    }


    // TODO: transfer account
    // TODO: delete account
    // TODO: follow account events
    // TODO: unfollow account events

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

        event::emit(AccountFollowEvent {
            follower_kid: follower.kid,
            following_kid: following.kid,
            follower: delegate.owner,
            following: following_address,
            kid,
            delegate: delegate_address,
            user_kid: follower.kid,
        })

    }

    public entry fun unfollow_account(delegate: &signer, kid: u64)acquires DelegateAccount, KadeAccount {

        let delegate_address = signer::address_of(delegate);
        let user_kid = get_delegate_owner(delegate);

        event::emit(AccountUnFollowEvent {
            delegate: delegate_address,
            user_kid,
            kid,
        })
    }


    public(friend) fun get_delegate_owner(delegate: &signer): u64 acquires DelegateAccount, KadeAccount {
        let delegate_address = signer::address_of(delegate);
        assert!(exists<DelegateAccount>(delegate_address), EDelegateDoesNotExist);

        let data = borrow_global<DelegateAccount>(delegate_address);

        let account_data = borrow_global<KadeAccount>(data.account_object_address);

        account_data.kid

    }

    public(friend) fun get_account_owner(account_address: address): KadeAccount acquires KadeAccount {
        let account_data = *borrow_global<KadeAccount>(account_address);
        account_data
    }


    #[test_only]
    public(friend)  fun invoke_init_module(admin: &signer) {
        init_module(admin);
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

        let state = borrow_global<State>(expeected_resource_address);

        assert!(state.registry_count == 0, 1);


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
        create_account(user, username);

        let account_creation_events = emitted_events<AccountCreateEvent>();

        assert!(vector::length(&account_creation_events) == 1, 1);

        let event = vector::borrow(&account_creation_events, 0);

        assert!(event.username == username, 2);

        let local_account_ref = borrow_global<LocalAccountReferences>(signer::address_of(user));

        let account = borrow_global<KadeAccount>(local_account_ref.object_address);

        assert!(account.username == username, 3);

        assert!(account.kid == 0, 4);

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
        let username = string::utf8(b"kade");
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
        let username = string::utf8(b"kade");
        create_account(user1, username);
        create_account(user2, username);

        add_account_delegate(user1, delegate);

        follow_account(delegate, signer::address_of(user2));

        let events = emitted_events<AccountFollowEvent>();

        assert!(vector::length(&events) == 1, 1);

        let event = vector::borrow(&events, 0);

        assert!(event.follower_kid == 0, 2);

        assert!(event.following_kid == 1, 3);

        assert!(event.follower == signer::address_of(user1), 4);

        assert!(event.following == signer::address_of(user2), 5);

        assert!(event.delegate == signer::address_of(delegate), 6);

        assert!(event.user_kid == 0, 7);

        debug::print(event);

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
        let username = string::utf8(b"kade");
        create_account(user1, username);
        create_account(user2, username);

        add_account_delegate(user1, delegate);

        follow_account(delegate, signer::address_of(user2));

        unfollow_account(delegate, 0);

        let events = emitted_events<AccountUnFollowEvent>();

        assert!(vector::length(&events) == 1, 1);

        let event = vector::borrow(&events, 0);

        assert!(event.delegate == signer::address_of(delegate), 2);

        assert!(event.user_kid == 0, 3);

        assert!(event.kid == 0, 4);

        debug::print(event);

    }



}
