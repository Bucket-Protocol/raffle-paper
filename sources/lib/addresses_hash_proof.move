// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Example of objects that can be combined to create
/// new objects
module raffle::addresses_hash_proof {
    friend raffle::drand_raffle_with_zero_knowledge_proof;
    
    use sui::object::{Self, ID, UID};
    use std::vector;
    use sui::tx_context::{Self, TxContext};
    use sui::object_table::{Self, ObjectTable};
    use std::bcs;
    use std::hash::{Self};
    use std::debug;

    // public fun hash_addresses(addresses: vector<address>): vector<u8> {
    //     let all_bytes = vector::empty<u8>();
    //     let index = 0;
    //     let len = vector::length(&addresses);
    //     while(index < len) {
    //         let byte = bcs::to_bytes(vector::borrow(&addresses, index));
    //         vector::append(&mut all_bytes, byte);
    //         index = index + 1
    //     };
    //     return hash::sha3_256(all_bytes)
    // }

    fun efficient_hash(a: vector<u8>, b: vector<u8>): vector<u8> {
        vector::append(&mut a, b);
        return hash::sha3_256(a)
    }

    public fun proof_user(participant: address, index: u64, proofs: vector<vector<u8>>, root: vector<u8>): bool{
        let leaf = efficient_hash(
            bcs::to_bytes(&index), 
            bcs::to_bytes(&participant)
        );
        debug::print(&leaf);
        return verify(leaf, proofs, root)
    }
    fun process_proof(leaf: vector<u8>, proofs: vector<vector<u8>>): vector<u8> {
        let index = 0;
        let proof_len = vector::length(&proofs);
        let computed_hash = leaf;
        while (index < proof_len) {
            let proof = vector::borrow_mut(&mut proofs, index);
            computed_hash = efficient_hash(computed_hash, *proof);
            index = index + 1
        };
        return computed_hash
    }
    public fun verify(leaf: vector<u8>, proofs: vector<vector<u8>>, root: vector<u8>): bool {
        let computed_hash = process_proof(leaf, proofs);
        return computed_hash == root
    }

    

#[test]
    fun test_merkle() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;

        // create test addresses representing users
        let user: address = @0x04d626ce8938318165fab01491095329aee67fd017a4a17fe2c981b8a9a569cc;
        let index: u64 = 0;
        let root = x"bd1d23e6665d7f010df630c66809c19733b79b03e5840a367fa22baf5bed58e4";
        let proofs = vector::empty<vector<u8>>();
        vector::push_back(&mut proofs, x"d7029dd97a4e80faa52e93913ab20e9e8b395a749667d8f5efeacf05bb3c9ec3");
        vector::push_back(&mut proofs, x"a78664e853e4a0d260452870ac93bd8bf8f2ffdefea73505c16f7ce55dd72088");
        vector::push_back(&mut proofs, x"eaa13e622a7f2652126114c66ed179d34ac6b91d7aa743712b5edecd3ef7ddb0");
        vector::push_back(&mut proofs, x"e619157d86c8246784e4274463365dc7b73b28aba57a8d6fe836f7195834ec51");
        vector::push_back(&mut proofs, x"a07d80f94badde6d27bc61c3c884b50a6542fd25c0d0c8e00772c7a1f884e94e");
        vector::push_back(&mut proofs, x"eb2d1603e76aead0dda29d0ceda35ec1a0da7a1271a4ba7e4cf0993fb3305160");
        vector::push_back(&mut proofs, x"a047a5b20681c670ffc7b46e9b892fb4b050dc9467af0fa744d52ee770a132f6");
        vector::push_back(&mut proofs, x"0f57ac550dcd8bcab90d573866fbe7604576a8968321d7e722f1f14427dc76f6");
        let result = proof_user(user, index, proofs, root);
        assert!(result, 0);
    }

    #[test]
    fun test() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        use std::string::{Self, String};

        // create test addresses representing users
        let user: address = @0x96d9a120058197fce04afcffa264f2f46747881ba78a91beb38f103c60e315ae;
        let addresses = vector::empty<address>();
        vector::push_back(&mut addresses, user);
        vector::push_back(&mut addresses, user);
        vector::push_back(&mut addresses, user);
        // let hash = hash_addresses(addresses);
        // let stringHash = object::id_from_bytes(hash);
        // // debug::print(&stringHash);
        // assert!(hash == x"6ac15cfb5b577f6ed7b38e6a5ee24c1e37f0d94115e088ea31d88c69e664ac8b", 0);
        
        let user: address = @0x04d626ce8938318165fab01491095329aee67fd017a4a17fe2c981b8a9a569cc;
        let i: u64 = 0;
        let i = bcs::to_bytes(&i);
        
        let a = bcs::to_bytes(&user);
        // debug::print(&i);
        // debug::print(&a);
        
        let h2 = efficient_hash(*&i, *&a);
        // debug::print(&h2);
        
        // debug::print(&a);
        vector::append(&mut i, a);
        // debug::print(&i);
        let h = hash::sha3_256(i);
        // debug::print(&h);
    }
}