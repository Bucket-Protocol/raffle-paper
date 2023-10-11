// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Example of objects that can be combined to create
/// new objects
module raffle::addresses_sub_obj {
    friend raffle::drand_raffle_with_object_table;
    friend raffle::addresses_obj;
    use sui::object::{Self, ID, UID};
    use std::vector;
    use sui::tx_context::{Self, TxContext};
    use sui::object_table::{Self, ObjectTable};
    use std::bcs;
    use std::hash::{Self};


    struct AddressesSubObj has key, store {
        id: UID,
        addresses: vector<address>,
    }

    


    public (friend) fun create(
        addresses: vector<address>,
        ctx: &mut TxContext
    ): AddressesSubObj{
        return AddressesSubObj {
            id: object::new(ctx),
            addresses: addresses,
        }
    }
    public (friend) fun append(
        addressesSubObj: &mut AddressesSubObj,
        addresses: vector<address>,
    ){
        vector::append(&mut addressesSubObj.addresses,addresses);
    }

    public (friend) fun size(
        addressesSubObj: &AddressesSubObj,
    ):u64{
        vector::length(&addressesSubObj.addresses)
    }


    public (friend) fun get_addresses(
        addressesSubObj: &AddressesSubObj,
    ):&vector<address>{
        &addressesSubObj.addresses
    }
    public (friend) fun get_addresses_mut(
        addressesSubObj: &mut AddressesSubObj,
    ):&mut vector<address>{
        &mut addressesSubObj.addresses
    }

    public (friend) fun destroy(addressesSubObj:  AddressesSubObj){
        let AddressesSubObj { id, addresses } = addressesSubObj;
        object::delete(id)
    }

    public (friend) fun table_keys_create(
        addresses: vector<address>,
        ctx: &mut TxContext
    ): (ObjectTable<ID, AddressesSubObj>, vector<ID>) {
        let addressesSubObjs_table = object_table::new<ID, AddressesSubObj>(ctx);
        let addressesSubObjs_keys = vector::empty<ID>();
        
        let addressesSubObj = create(addresses, ctx);
        let id = object::id(&addressesSubObj);
        object_table::add(&mut addressesSubObjs_table, id, addressesSubObj);
        vector::push_back(&mut addressesSubObjs_keys, id);
        return (addressesSubObjs_table, addressesSubObjs_keys)
    }
    public (friend) fun table_keys_get_all_addresses(
        addressesSubObjs_table: &ObjectTable<ID, AddressesSubObj>,
        addressesSubObjs_keys: &vector<ID>,
    ):vector<address>{
        let index = 0;
        let all_addresses = vector::empty<address>();
        while (index < vector::length(addressesSubObjs_keys)) {
            let id = vector::borrow(addressesSubObjs_keys, index);
            let addressesSubObj = object_table::borrow(addressesSubObjs_table, *id);
            let subObjAddresses = get_addresses(addressesSubObj);
            let subIndex = 0;
            while (subIndex < vector::length(subObjAddresses)) {
                let address = vector::borrow(subObjAddresses, subIndex);
                vector::push_back(&mut all_addresses, *address);
                subIndex = subIndex + 1;
            };
            index = index + 1;
        };
        return all_addresses
    }
    public (friend) fun table_keys_clear(
        addressesSubObjs_table: &mut ObjectTable<ID, AddressesSubObj>,
        addressesSubObjs_keys: &mut vector<ID>,
    ):vector<address>{
        let index = 0;
        let all_addresses = vector::empty<address>();
        while (index < vector::length(addressesSubObjs_keys)) {
            let id = vector::remove(addressesSubObjs_keys, index);
            let addressesSubObj = object_table::remove(addressesSubObjs_table, id);
            destroy(addressesSubObj);
            index = index + 1;
        };
        return all_addresses
    }

    // #[test]
    // fun test() {
    //     use raffle::test_coin::{Self, TEST_COIN};
    //     use sui::test_scenario;
    //     use sui::balance;
    //     use std::debug;

    // }
}
