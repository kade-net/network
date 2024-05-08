
module kade::utils {

    use std::signer;
    use std::string;
    use hermes::request_inbox;
    use kade::accounts;
    use kade::usernames;
    #[test_only]
    use aptos_framework::account;
    #[test_only]
    use aptos_framework::timestamp;
    #[test_only]
    use kade::publications;


    const EUsernameNotRegistered: u64 = 21;
    const EUsernameNotOwned: u64 = 22;
    const EUsernameAlreadyRegistered: u64 = 23;

    public entry fun init_self_delegate_kade_account_with_hermes_inbox(user: &signer, username: string::String, publicKey: string::String){
        accounts::account_setup_with_self_delegate(user,username);
        request_inbox::register_request_inbox(user, publicKey);
    }


    public entry fun init_kade_account_with_hermes_inbox_and_delegate(user: &signer, username: string::String, delegate_address: address, accountPublicKey: string::String){
        let username_exists = usernames::is_username_claimed(username);

        if(username_exists){
            let owns_username = usernames::is_address_username_owner(signer::address_of(user), username);
            assert!(owns_username, EUsernameNotOwned);
        }else{
            usernames::friend_claim_username(user,username);
        };

        accounts::create_account_and_delegate_link_intent(user, delegate_address, username);
        request_inbox::register_request_inbox(user, accountPublicKey);
        request_inbox::create_delegate_link_intent(user, delegate_address);
    }


    #[test]
    fun test_init_kade_account_with_hermes_inbox(){
        let admin = account::create_account_for_test(@kade);
        let user = account::create_account_for_test(@0x445);
        let hermes = account::create_account_for_test(@hermes);
        // let delegate = account::create_account_for_test(@0x555);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        request_inbox::init_request_inbox(&hermes);
        usernames::dependancy_test_init_module(&admin);
        accounts::dependancy_test_init_module(&admin);
        publications::dependancy_test_init_module(&admin);
        init_self_delegate_kade_account_with_hermes_inbox(&user,string::utf8(b"hilda"), string::utf8(b""));

    }

    #[test]
    fun test_init_kade_account_with_hermes_inbox_and_delegate_link_intent(){
        let admin = account::create_account_for_test(@kade);
        let user = account::create_account_for_test(@0x445);
        let hermes = account::create_account_for_test(@hermes);
        let delegate = account::create_account_for_test(@0x555);
        let aptos = account::create_account_for_test(@0x1);

        timestamp::set_time_has_started_for_testing(&aptos);

        request_inbox::init_request_inbox(&hermes);
        usernames::dependancy_test_init_module(&admin);
        accounts::dependancy_test_init_module(&admin);
        publications::dependancy_test_init_module(&admin);
        init_kade_account_with_hermes_inbox_and_delegate(&user,string::utf8(b"hilda"), signer::address_of(&delegate),string::utf8(b""));
    }

}
