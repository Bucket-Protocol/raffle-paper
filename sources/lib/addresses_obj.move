// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Example of objects that can be combined to create
/// new objects
module raffle::addresses_obj {
    // friend raffle::nft_raffle;
    friend raffle::drand_raffle_with_object_table;
    
    use sui::clock::{Self, Clock};
    use raffle::drand_lib::{derive_randomness, verify_drand_signature, safe_selection, get_current_round_by_time};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use std::string::{Self, String};
    use std::ascii::String as ASCIIString;
    use sui::event;
    use std::type_name;
    use sui::object::{Self, ID, UID};
    use sui::object_table::{Self, ObjectTable};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use raffle::addresses_sub_obj::{Self, AddressesSubObj};


    struct AddressesObj<phantom T> has key, store {
        id: UID,
        addressesSubObjs_table: ObjectTable<ID, AddressesSubObj>,
        addressesSubObjs_keys: vector<ID>,
        creator: address,
        fee: u64,
    }

    public (friend) fun internal_create<T>(
        addresses: vector<address>,
        ctx: &mut TxContext
    ): AddressesObj<T> {
        let (
            addressesSubObjs_table,
            addressesSubObjs_keys
        ) = addresses_sub_obj::table_keys_create(addresses, ctx);
        
        // object_table::add(&mut reward_nfts, id, nft);
        let addressesObj = AddressesObj<T> {
            id: object::new(ctx),
            addressesSubObjs_table,
            addressesSubObjs_keys,
            creator: tx_context::sender(ctx),
            fee:0,
        };
        return addressesObj
    }
    public entry fun create<T>(
        participants: vector<address>,
        ctx: &mut TxContext
    ){
        let addressesObj = internal_create<T>(participants, ctx);
        transfer::transfer(addressesObj, tx_context::sender(ctx));
    }
    
    public entry fun add_addresses<T>(
        addressesObj: &mut AddressesObj<T>,
        addresses: vector<address>, 
        ctx: &mut TxContext
    ){
        let id = vector::borrow(
            &addressesObj.addressesSubObjs_keys, 
            vector::length(&addressesObj.addressesSubObjs_keys) - 1,
        );
        let latestSubObj = object_table::borrow_mut(&mut addressesObj.addressesSubObjs_table, *id);
        if(addresses_sub_obj::size(latestSubObj) + vector::length(&addresses) > 7600){
            let addressesSubObj = addresses_sub_obj::create(addresses, ctx);
            let id = object::id(&addressesSubObj);
            object_table::add(&mut addressesObj.addressesSubObjs_table, id, addressesSubObj);
            vector::push_back(&mut addressesObj.addressesSubObjs_keys, id);
        }else{
            addresses_sub_obj::append(latestSubObj, addresses);
        }
    }
    public entry fun finalize<T>(
        addressesObj: AddressesObj<T>,
        fee: u64,
        ctx: &mut TxContext
    ){
        assert!(addressesObj.creator == tx_context::sender(ctx),1);
        setFee(&mut addressesObj, fee);
        let AddressesObj<T> {
            id,
            addressesSubObjs_table,
            addressesSubObjs_keys,
            creator,
            fee
        } = addressesObj;
        object::delete(id);
        let addressesObj = AddressesObj<T> {
            id: object::new(ctx),
            addressesSubObjs_table,
            addressesSubObjs_keys,
            creator,
            fee,
        };
        transfer::public_share_object(addressesObj);
    }

    public (friend) fun setFee<T>(
        addressesObj: &mut AddressesObj<T>,
        fee: u64,
    ){
        addressesObj.fee = fee;
    }

    public entry fun destroy<T>(
        addressesObj: AddressesObj<T>,
    ){
        assert!(addressesObj.fee == 0, 0);
        let AddressesObj<T> {
            id,
            addressesSubObjs_table,
            addressesSubObjs_keys,
            creator,
            fee
        } = addressesObj;
        object::delete(id);
        addresses_sub_obj::table_keys_clear(&mut addressesSubObjs_table, &mut addressesSubObjs_keys);
        object_table::destroy_empty(addressesSubObjs_table);
        vector::destroy_empty(addressesSubObjs_keys);
    }

    public (friend) fun pop_all<T>(
        addressesObj: &mut AddressesObj<T>,
        ctx: &mut TxContext
    ): (ObjectTable<ID, AddressesSubObj>, vector<ID>) {
        let out_table = object_table::new<ID, AddressesSubObj>(ctx);
        let index = 0;
        while (index < vector::length(&addressesObj.addressesSubObjs_keys)) {
            let id = vector::borrow(&addressesObj.addressesSubObjs_keys, index);
            let addressesSubObj = object_table::remove(&mut addressesObj.addressesSubObjs_table, *id);
            object_table::add(&mut out_table, *id, addressesSubObj);
            index = index + 1;
        };
        let out_keys = addressesObj.addressesSubObjs_keys;
        addressesObj.addressesSubObjs_keys = vector::empty();
        return (out_table, out_keys)
    }
    public (friend) fun clear<T>(
        addressesObj: &mut AddressesObj<T>,
    ){
        let index = 0;
        while (index < vector::length(&addressesObj.addressesSubObjs_keys)) {
            let id = vector::borrow(&addressesObj.addressesSubObjs_keys, index);
            let addressesSubObj = object_table::remove(&mut addressesObj.addressesSubObjs_table, *id);
            addresses_sub_obj::destroy(addressesSubObj);
            index = index + 1;
        };
        addressesObj.addressesSubObjs_keys = vector::empty();
    }
    public entry fun clearByCreator<T>(
        addressesObj: &mut AddressesObj<T>,
        ctx: &mut TxContext
    ){
        assert!(addressesObj.creator == tx_context::sender(ctx),1);
        clear(addressesObj);
    }
    

    public fun getAddresses<T>(
        addressesObj: &AddressesObj<T>,
    ): vector<address> {
        addresses_sub_obj::table_keys_get_all_addresses(
            &addressesObj.addressesSubObjs_table, 
            &addressesObj.addressesSubObjs_keys,
        )
    }
    public fun getCreator<T>(
        addressesObj: &AddressesObj<T>,
    ): address {
        return addressesObj.creator
    }
    public fun getFee<T>(
        addressesObj: &AddressesObj<T>,
    ): u64 {
        return addressesObj.fee
    }

    #[test]
    fun test() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;

        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xCAF1;
        let user2 = @0xCAF2;
        let user3 = @0xCAF3;
        let user4 = @0xCAF4;
        let user5 = @0xCAF5;
        let user6 = @0xCAF6;
        let user7 = @0xCAF7;
        
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        
        {
            let participants = vector::empty<address>();
            vector::push_back(&mut participants, user1);
            vector::push_back(&mut participants, user2);
            vector::push_back(&mut participants, user3);
            vector::push_back(&mut participants, user4);
            vector::push_back(&mut participants, user5);
            vector::push_back(&mut participants, user6);
            vector::push_back(&mut participants, user7);
            create<TEST_COIN>(participants, test_scenario::ctx(scenario));
        };
        
        let i = 0;
        while(i < 100){
            test_scenario::next_tx(scenario, admin);
            {
                let addressesObj = test_scenario::take_from_address<AddressesObj<TEST_COIN>>(scenario, admin);
                let participants = vector::empty<address>();
                vector::push_back(&mut participants, user1);
                vector::push_back(&mut participants, user2);
                vector::push_back(&mut participants, user3);
                vector::push_back(&mut participants, user4);
                vector::push_back(&mut participants, user5);
                vector::push_back(&mut participants, user6);
                vector::push_back(&mut participants, user7);
                add_addresses(&mut addressesObj, participants, test_scenario::ctx(scenario));
                test_scenario::return_to_address(admin, addressesObj);
            };
            i = i+1;
        };
        test_scenario::next_tx(scenario, admin);
        let fee = 50000;
        {
            let addressesObj = test_scenario::take_from_address<AddressesObj<TEST_COIN>>(scenario, admin);
            finalize(addressesObj, fee, test_scenario::ctx(scenario));
        };

        // test_scenario::next_tx(scenario, host);
        // {
        //     let addressesObj = test_scenario::take_shared<AddressesObj<TEST_COIN>>(scenario);
        //     assert!(addressesObj.fee == fee, 0);
        //     clear(&mut addressesObj);
        //     setFee(&mut addressesObj, 0);
        //     assert!(vector::length(&addressesObj.addressesSubObjs_keys) == 0, 0);
        //     test_scenario::return_shared(addressesObj);
        // };
        test_scenario::end(scenario_val);
    }
}
