
/**
    This contract is responsible for all new registration of kade usernames and validating if they already exist or not
**/

module kade::usernames {

    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::event::{emit_event, emit};
    use aptos_framework::object;
    use aptos_framework::object::ExtendRef;
    use aptos_framework::timestamp;
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    #[test_only]
    use aptos_std::debug;

    friend kade::accounts;
    friend kade::publications;
    friend kade::utils;

    const SEED:vector<u8> = b"kade::usernamesv1";

    const COLLECTION_NAME: vector<u8> = b"Kade Usernames Registry";
    const COLLECTION_DESCRIPTION: vector<u8> = b"Kade's Registered Usernames";
    const COLLECTION_URI: vector<u8> = b"https://kade.network";

    const IDENTITY_IMAGE:vector<u8> = b"https://orange-urban-sloth-806.mypinata.cloud/ipfs/QmP2uYhKYUHSB587AfQvLb7hdeN5vTpfp6MC81KL98mf5E";


    //  Errors
    const EOperationNotPermited: u64 = 200;
    const EUsernameAlreadyClaimed: u64 = 201;
    const EINVALID_USERNAME: u64 = 202;

    struct RegisterUsernameEvent has store, drop {
        username: string::String,
        owner_address: address,
        token_address: address,
        timestamp: u64,
    }

    struct UsernameRegistry has key {
        registered_usernames: u64,
        signer_capability: account::SignerCapability,
        registration_events: event::EventHandle<RegisterUsernameEvent>
    }

    struct UserNameRecord has key {
        username: string::String,
        target_address: address,
        transfer_ref: object::TransferRef,
        extend_ref: ExtendRef,
    }

    #[event]
    struct UserNameReclaimed has store, drop {
        username: string::String,
        old_owner_address: address,
        timestamp: u64
    }

    fun init_module(admin: &signer) {


        let (resource_account_signer, signer_capability) = account::create_resource_account(admin, SEED);

        collection::create_unlimited_collection(
            &resource_account_signer,
            string::utf8(COLLECTION_DESCRIPTION),
            string::utf8(COLLECTION_NAME),
            option::none(),
            string::utf8(COLLECTION_URI)
        );

        let registry = UsernameRegistry {
            signer_capability,
            registration_events: account::new_event_handle(&resource_account_signer),
            registered_usernames: 100 // The first 100 ids are reserved for system error codes
        };

        move_to<UsernameRegistry>(&resource_account_signer, registry);
    }


    fun internal_claim_username(username: string::String, address: address) acquires UsernameRegistry, UserNameRecord {
        let resource_address = account::create_resource_address(&@kade, SEED);

        let registry = borrow_global_mut<UsernameRegistry>(resource_address);
        let resource_signer = account::create_signer_with_capability(&registry.signer_capability);

        let has_been_claimed = has_username_been_reclaimed(username);

        if(has_been_claimed){

            reclaim_deleted_username(address, username);
            let token_address = get_username_token_address(username);

            emit_event(&mut registry.registration_events, RegisterUsernameEvent {
                username,
                token_address,
                timestamp: timestamp::now_seconds(),
                owner_address: address,
            });

            return
        };

        let string_length = string::length(&username);
        assert!(string_length < 32, EINVALID_USERNAME);
        assert!(string_length > 0, EINVALID_USERNAME);
        let index_of_empty_string = string::index_of(&username, &string::utf8(b" "));
        assert!(index_of_empty_string == string_length, EINVALID_USERNAME);
        assert_has_no_special_characters(username);


        let token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &username);

        let is_object = object::is_object(token_address);


        assert!(!is_object, EUsernameAlreadyClaimed);
        assert!(!exists<UserNameRecord>(token_address), EUsernameAlreadyClaimed);

        let constructor_ref = token::create_named_token(
            &resource_signer,
            string::utf8(COLLECTION_NAME),
            string::utf8(COLLECTION_DESCRIPTION),
            username,
            option::none(),
            string::utf8(IDENTITY_IMAGE)
        );
        let token_signer = object::generate_signer(&constructor_ref);

        let record = UserNameRecord {
            username,
            transfer_ref: object::generate_transfer_ref(&constructor_ref),
            extend_ref: object::generate_extend_ref(&constructor_ref),
            target_address: address,
        };

        move_to(&token_signer, record);

        let record_obj = object::object_from_constructor_ref<UserNameRecord>(&constructor_ref);

        object::transfer(&resource_signer, record_obj, address);

        object::disable_ungated_transfer(&object::generate_transfer_ref(&constructor_ref));

        // Increment the registry names
        registry.registered_usernames = registry.registered_usernames + 1;

        emit_event(&mut registry.registration_events, RegisterUsernameEvent {
            username,
            token_address: signer::address_of(&token_signer),
            timestamp: timestamp::now_seconds(),
            owner_address: address,
        })

    }

    public entry fun claim_username(user: &signer, username: string::String) acquires  UsernameRegistry, UserNameRecord {
        // TODO: we may decentralize this functionality later
        assert!(signer::address_of(user) == @kade, EOperationNotPermited);
        internal_claim_username(username, signer::address_of(user));
    }

    public(friend) entry fun friend_claim_username(user: &signer, username: string::String) acquires UsernameRegistry, UserNameRecord {
        internal_claim_username(username, signer::address_of(user));
    }

    public entry fun gd_claim_username(admin: &signer, username: string::String, address: address) acquires  UsernameRegistry, UserNameRecord {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermited);
        internal_claim_username(username, address)
    }

    fun internal_delete_username(user_address: address, username: string::String) acquires UserNameRecord {
        assert!(is_username_claimed(username), EINVALID_USERNAME);
        assert!(is_address_username_owner(user_address, username), EOperationNotPermited);
        let resource_address = account::create_resource_address(&@kade, SEED);
        let token_address = get_username_token_address(username);
        let record = borrow_global_mut<UserNameRecord>(token_address);
        // reassign to resource account
        record.target_address = resource_address;
        let linear_transfer_ref = object::generate_linear_transfer_ref(&record.transfer_ref);
        object::transfer_with_ref(linear_transfer_ref, resource_address);

        emit(UserNameReclaimed {
            username,
            timestamp: timestamp::now_seconds(),
            old_owner_address: user_address
        })
    }


    public entry fun admin_delete_username(admin: &signer, user_address: address, username: string::String) acquires UserNameRecord {
        assert!(signer::address_of(admin) == @kade, EOperationNotPermited);
        internal_delete_username(user_address, username);
    }

    // TODO: transfer ownership of username to another user


    fun reclaim_deleted_username(user_address: address, username: string::String) acquires UserNameRecord {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &username);

        let username_record = borrow_global_mut<UserNameRecord>(token_address);
        username_record.target_address = user_address;

        let linear_transfer_ref = object::generate_linear_transfer_ref(&username_record.transfer_ref);

        object::transfer_with_ref(linear_transfer_ref, user_address);
    }


    #[view]
    public fun is_username_claimed(username: string::String): bool acquires UserNameRecord {
        let reclaimed = has_username_been_reclaimed(username);
        if(reclaimed){
            return false
        };
        let resource_address = account::create_resource_address(&@kade, SEED);
        let token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &username);

        let is_object = object::is_object(token_address);

        is_object

    }

    #[view]
    public fun has_username_been_reclaimed(username: string::String): bool acquires UserNameRecord {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &username);

        let is_object = object::is_object(token_address);

        if(!is_object){
            return false
        };

        let record = borrow_global<UserNameRecord>(token_address);
        let has_been_reclaimed = record.target_address == resource_address;
        has_been_reclaimed
    }

    #[view]
    public fun is_address_username_owner(user_address: address, username: string::String): bool {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &username);

        let is_object = object::is_object(token_address);

        if(is_object) {
            let record = object::address_to_object<UserNameRecord>(token_address);

            let is_owner = object::is_owner(record, user_address);

            is_owner
        }
        else {
            false
        }
    }

    #[view]
    public fun get_username_token_address(username: string::String): address {
        let resource_address = account::create_resource_address(&@kade, SEED);
        let token_address = token::create_token_address(&resource_address, &string::utf8(COLLECTION_NAME), &username);

        token_address
    }


    // ======
    // Helper functions
    // =====
    inline fun assert_has_no_special_characters(username: string::String){
        let string_length = string::length(&username);
        assert!(string_length < 32, EINVALID_USERNAME);
        let index_of_empty_string = string::index_of(&username, &string::utf8(b" "));
        assert!(index_of_empty_string == string_length, EINVALID_USERNAME);

        let special_characters = vector::empty<string::String>();
        vector::push_back(&mut special_characters, string::utf8(b"!"));
        vector::push_back(&mut special_characters, string::utf8(b"@"));
        vector::push_back(&mut special_characters, string::utf8(b"#"));
        vector::push_back(&mut special_characters, string::utf8(b"$"));
        vector::push_back(&mut special_characters, string::utf8(b"%"));
        vector::push_back(&mut special_characters, string::utf8(b"^"));
        vector::push_back(&mut special_characters, string::utf8(b"&"));
        vector::push_back(&mut special_characters, string::utf8(b"*"));
        vector::push_back(&mut special_characters, string::utf8(b"("));
        vector::push_back(&mut special_characters, string::utf8(b")"));
        vector::push_back(&mut special_characters, string::utf8(b"-"));
        vector::push_back(&mut special_characters, string::utf8(b"+"));
        vector::push_back(&mut special_characters, string::utf8(b"="));
        vector::push_back(&mut special_characters, string::utf8(b"["));
        vector::push_back(&mut special_characters, string::utf8(b"]"));
        vector::push_back(&mut special_characters, string::utf8(b"{"));
        vector::push_back(&mut special_characters, string::utf8(b"}"));
        vector::push_back(&mut special_characters, string::utf8(b"|"));
        vector::push_back(&mut special_characters, string::utf8(b";"));
        vector::push_back(&mut special_characters, string::utf8(b":"));
        vector::push_back(&mut special_characters, string::utf8(b"'"));
        vector::push_back(&mut special_characters, string::utf8(b"\""));
        vector::push_back(&mut special_characters, string::utf8(b"<"));
        vector::push_back(&mut special_characters, string::utf8(b">"));
        vector::push_back(&mut special_characters, string::utf8(b","));
        vector::push_back(&mut special_characters, string::utf8(b"."));
        vector::push_back(&mut special_characters, string::utf8(b"/"));
        vector::push_back(&mut special_characters, string::utf8(b"?"));
        vector::push_back(&mut special_characters, string::utf8(b"`"));
        vector::push_back(&mut special_characters, string::utf8(b"~"));
        vector::push_back(&mut special_characters, string::utf8(b" "));
        vector::push_back(&mut special_characters, string::utf8(b"\t"));
        vector::push_back(&mut special_characters, string::utf8(b"\n"));
        vector::push_back(&mut special_characters, string::utf8(b"\r"));
        vector::push_back(&mut special_characters, string::utf8(b"\0"));
        vector::push_back(&mut special_characters, string::utf8(b"A"));
        vector::push_back(&mut special_characters, string::utf8(b"B"));
        vector::push_back(&mut special_characters, string::utf8(b"C"));
        vector::push_back(&mut special_characters, string::utf8(b"D"));
        vector::push_back(&mut special_characters, string::utf8(b"E"));
        vector::push_back(&mut special_characters, string::utf8(b"F"));
        vector::push_back(&mut special_characters, string::utf8(b"G"));
        vector::push_back(&mut special_characters, string::utf8(b"H"));
        vector::push_back(&mut special_characters, string::utf8(b"I"));
        vector::push_back(&mut special_characters, string::utf8(b"J"));
        vector::push_back(&mut special_characters, string::utf8(b"K"));
        vector::push_back(&mut special_characters, string::utf8(b"L"));
        vector::push_back(&mut special_characters, string::utf8(b"M"));
        vector::push_back(&mut special_characters, string::utf8(b"N"));
        vector::push_back(&mut special_characters, string::utf8(b"O"));
        vector::push_back(&mut special_characters, string::utf8(b"P"));
        vector::push_back(&mut special_characters, string::utf8(b"Q"));
        vector::push_back(&mut special_characters, string::utf8(b"R"));
        vector::push_back(&mut special_characters, string::utf8(b"S"));
        vector::push_back(&mut special_characters, string::utf8(b"T"));
        vector::push_back(&mut special_characters, string::utf8(b"U"));
        vector::push_back(&mut special_characters, string::utf8(b"V"));
        vector::push_back(&mut special_characters, string::utf8(b"W"));
        vector::push_back(&mut special_characters, string::utf8(b"X"));
        vector::push_back(&mut special_characters, string::utf8(b"Y"));
        vector::push_back(&mut special_characters, string::utf8(b"Z"));

        let current_index = 0;
        let special_characters_length = vector::length(&special_characters);
        while(current_index < special_characters_length) {
            let special_character = vector::borrow(&special_characters, current_index);
            let index_of_special_character = string::index_of(&username, special_character);
            assert!(index_of_special_character == string_length, EINVALID_USERNAME);
            current_index = current_index + 1;
        }

    }


    #[test_only]
    public fun dependancy_test_init_module(test_admin: &signer) {
        init_module(test_admin);
    }


    // =====
    // TESTS
    // =====
    #[test]
    fun test_init_module_success() acquires UsernameRegistry {
        let admin_signer = account::create_account_for_test(@kade);
        account::create_account_for_test(@0x1);

        init_module(&admin_signer);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        debug::print(&expected_resource_address);

        let registry = borrow_global<UsernameRegistry>(expected_resource_address);

        assert!(registry.registered_usernames == 100, 1)

    }

    #[test]
    fun test_internal_claim_username() acquires UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);

        internal_claim_username(string::utf8(b"kade"), @kade);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let registry = borrow_global<UsernameRegistry>(expected_resource_address);

        assert!(registry.registered_usernames == 101, 1);

        let count = event::counter(&registry.registration_events);

        assert!(count == 1, 2);

        let token_address = token::create_token_address(&expected_resource_address, &string::utf8(COLLECTION_NAME), &string::utf8(b"kade"));

        let is_object = object::is_object(token_address);

        assert!(is_object, 3);
        assert!(exists<UserNameRecord>(token_address), 4);

        let token_obj = object::address_to_object<UserNameRecord>(token_address);

        assert!(object::is_owner(token_obj, @kade), 5);

    }

    #[test_only]
    public(friend)  fun invoke_init_module(admin: &signer) {
        init_module(admin);
    }

    #[test]
    #[expected_failure(abort_code = EUsernameAlreadyClaimed)]
    fun test_no_multi_claim() acquires UsernameRegistry, UserNameRecord{
        let admin_signer = account::create_account_for_test(@kade);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);

        internal_claim_username(string::utf8(b"kade"), @kade);
        internal_claim_username(string::utf8(b"kade"), @0x6);
    }

    #[test]
    fun test_claim_username() acquires  UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        let user = account::create_account_for_test(@0x5);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);
        internal_claim_username( string::utf8(b"jurassic"), signer::address_of(&user));
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_USERNAME)]
    fun test_invalid_username() acquires  UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        let user = account::create_account_for_test(@0x5);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);

        internal_claim_username(string::utf8(b"jurassic p#rk"), signer::address_of(&user) );
    }

    #[test]
    fun test_gas_deffered_claim() acquires  UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        account::create_account_for_test(@0x5);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);

        gd_claim_username(&admin_signer, string::utf8(b"dev"), @0x5);

        let expected_resource_address = account::create_resource_address(&@kade, SEED);

        let registry = borrow_global<UsernameRegistry>(expected_resource_address);

        assert!(registry.registered_usernames == 101, 1);

        let count = event::counter(&registry.registration_events);

        assert!(count == 1, 2);

        let token_address = token::create_token_address(&expected_resource_address, &string::utf8(COLLECTION_NAME), &string::utf8(b"dev"));

        let is_object = object::is_object(token_address);

        assert!(is_object, 3);
        assert!(exists<UserNameRecord>(token_address), 4);

        let token_obj = object::address_to_object<UserNameRecord>(token_address);

        assert!(object::is_owner(token_obj, @0x5), 5);


    }

    #[test]
    fun test_is_username_claimed() acquires UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);

        internal_claim_username(string::utf8(b"kade"), @kade);

        let claimed = is_username_claimed(string::utf8(b"kade"));

        let not_claimed = is_username_claimed(string::utf8(b"dev"));

        assert!(!not_claimed, 2);

        assert!(claimed, 1);
    }

    #[test]
    fun test_is_address_owner() acquires UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);

        internal_claim_username(string::utf8(b"kade"), @kade);

        let is_owner = is_address_username_owner(@kade, string::utf8(b"kade"));

        assert!(is_owner, 1);

        let is_not_owner = is_address_username_owner(@0x1, string::utf8(b"kade"));

        assert!(!is_not_owner, 2);
    }


    #[test]
    fun test_delete_username() acquires  UsernameRegistry, UserNameRecord {
        let admin_signer = account::create_account_for_test(@kade);
        let user = account::create_account_for_test(@0x5);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        init_module(&admin_signer);
        internal_claim_username( string::utf8(b"jurassic"), signer::address_of(&user));

        internal_delete_username(signer::address_of(&user), string::utf8(b"jurassic"));

    }



}
