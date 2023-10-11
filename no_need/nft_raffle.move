// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Example of objects that can be combined to create
/// new objects
module raffle::nft_raffle {
    use sui::clock::{Self, Clock};
    use raffle::drand_lib::{derive_randomness, verify_drand_signature, safe_selection, get_current_round_by_time};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, ID, UID};
    use sui::object_table::{Self, ObjectTable};
    use sui::transfer;
    use sui::event;
    use std::type_name;
    use std::string::String;
    use std::ascii::String as ASCIIString;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use std::string::{Self};
    use raffle::addresses_obj::{Self, AddressesObj};
    use raffle::addresses_sub_obj::{Self, AddressesSubObj};
    use raffle::addresses_hash_proof;
    
    struct NFT_Raffle <phantom T: store + key> has key, store {
        id: UID,
        name: String,
        round: u64,
        status: u8,
        creator: address,
        settler: address,
        addressesSubObjs_table: ObjectTable<ID, AddressesSubObj>,
        addressesSubObjs_keys: vector<ID>,
        reward_nfts: ObjectTable<ID, T>,
        reward_nfts_table_keys: vector<ID>,
        participantCount: u64,
        winnerCount: u64,
        winners: vector<address>,
    }
    /// Raffle status
    const IN_PROGRESS: u8 = 0;
    const COMPLETED: u8 = 1;

    
    fun init(_ctx: &mut TxContext) {
    }

    struct NftRaffleCreated has copy, drop {
        raffle_id: ID,
        raffle_name: String,
        creator: address,
        round: u64,
        participants_count: u64,
        // participants_hash_proof: ID,
        winnerCount: u64,
        prizeType: ASCIIString,
        reward_nft_ids: vector<ID>,
    }
    public fun emit_nft_raffle_created<T: store + key>(raffle: &NFT_Raffle<T>) {
        let raffleType = type_name::into_string(type_name::get<T>());
        let raffleId = *object::borrow_id(raffle);
        let participants = getParticipants(raffle);
        // let participants_hash_proof = object::id_from_bytes(addresses_hash_proof::hash_addresses(participants));
        event::emit(NftRaffleCreated {
            raffle_id: raffleId,
            raffle_name: raffle.name,
            creator: raffle.creator,
            round: raffle.round,
            participants_count: vector::length(&participants),
            // participants_hash_proof,
            winnerCount: raffle.winnerCount,
            prizeType: raffleType,
            reward_nft_ids: raffle.reward_nfts_table_keys,
            }
        );
    }
    struct NftRaffleSettled has copy, drop {
        raffle_id: ID,
        settler: address,
        winners: vector<address>,
    }
    public fun emit_nft_raffle_settled<T: store + key>(raffle: &NFT_Raffle<T>) {
        let raffleId = *object::borrow_id(raffle);
        event::emit(NftRaffleSettled {
            raffle_id: raffleId,
            settler: raffle.settler,
            winners: raffle.winners,
            }
        );
    }

    fun internal_create_nft_raffle<T: store + key>(
        name: vector<u8>,
        clock: &Clock,
        addressesSubObjs_table: ObjectTable<ID, AddressesSubObj>,
        addressesSubObjs_keys: vector<ID>,
        reward_nfts_vec: vector<T>, 
        ctx: &mut TxContext
    ){
        let participants = addresses_sub_obj::table_keys_get_all_addresses(&addressesSubObjs_table, &addressesSubObjs_keys);
        let participantCount = vector::length(&participants);
        let winnerCount = vector::length(&reward_nfts_vec);
        assert!(winnerCount <= participantCount, 0);

        let drand_current_round = get_current_round_by_time(clock::timestamp_ms(clock));
        
        let idx: u64 = 0;
        let reward_nfts = object_table::new(ctx);
        let reward_nfts_table_keys = vector::empty<ID>();
        while (!vector::is_empty(&reward_nfts_vec)) {
            let nft = vector::pop_back(&mut reward_nfts_vec);
            let id = object::id(&nft);
            object_table::add(&mut reward_nfts, id, nft);
            vector::push_back(&mut reward_nfts_table_keys, id);
            idx = idx + 1;
        };
        let raffle: NFT_Raffle<T> = NFT_Raffle {
            id: object::new(ctx),
            name: string::utf8(name),
            round: drand_current_round + 2,
            status: IN_PROGRESS,
            creator: tx_context::sender(ctx),
            settler: @0x00,
            addressesSubObjs_table,
            addressesSubObjs_keys,
            reward_nfts: reward_nfts,
            reward_nfts_table_keys: reward_nfts_table_keys,
            participantCount,
            winnerCount,
            winners: vector::empty(),
        };
        emit_nft_raffle_created(&raffle);
        transfer::public_share_object(raffle);
        vector::destroy_empty(reward_nfts_vec);
    }
    public entry fun create_nft_raffle_by_addresses_obj<T: store + key, F: drop>(
        name: vector<u8>,
        clock: &Clock,
        addressesObj: &mut AddressesObj<F>,
        fee: Coin<F>,
        reward_nfts_vec: vector<T>, 
        ctx: &mut TxContext
    ){
        assert!(addresses_obj::getFee(addressesObj) == balance::value(coin::balance(&fee)), 0);
        transfer::public_transfer(fee, addresses_obj::getCreator(addressesObj));
        addresses_obj::setFee(addressesObj, 0);
        let (addressesSubObjs_table, addressesSubObjs_keys) = addresses_obj::pop_all(addressesObj, ctx);
        internal_create_nft_raffle(name, clock, addressesSubObjs_table, addressesSubObjs_keys, reward_nfts_vec, ctx);
    }
    public entry fun create_nft_raffle<T: store + key>(
        name: vector<u8>,
        clock: &Clock,
        participants: vector<address>, 
        reward_nfts_vec: vector<T>, 
        ctx: &mut TxContext
    ){
        let (
            addressesSubObjs_table,
            addressesSubObjs_keys
        ) = addresses_sub_obj::table_keys_create(participants, ctx);
        internal_create_nft_raffle(name, clock, addressesSubObjs_table, addressesSubObjs_keys, reward_nfts_vec, ctx);
    }

    public entry fun settle_nft_raffle<T: store + key>(
        raffle: &mut NFT_Raffle<T>, 
        clock: &Clock,
        drand_sig: vector<u8>, 
        drand_prev_sig: vector<u8>, 
        ctx: &mut TxContext,
    ) {
        assert!(raffle.status != COMPLETED, 0);
        if(raffle.creator != tx_context::sender(ctx)){
            let currend_round = get_current_round_by_time(clock::timestamp_ms(clock));
            assert!(currend_round >= raffle.round + 10, 0);
        };
        verify_drand_signature(drand_sig, drand_prev_sig, raffle.round);
        raffle.status = COMPLETED;
        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = derive_randomness(drand_sig);
        let random_number = 0;
        let participants = getParticipants(raffle);
        let i = 0;
        loop{
            i = i+1;
            let length = vector::length(&participants);
            let random_number = safe_selection(length, &digest, random_number);
            let winner = vector::swap_remove(&mut participants, random_number);
            vector::push_back<address>(
                &mut raffle.winners, 
                winner,
            );
            let id = vector::pop_back(&mut raffle.reward_nfts_table_keys);
            let nft = object_table::remove(&mut raffle.reward_nfts, id);
            if (i < raffle.winnerCount) {
                transfer::public_transfer(nft, winner);
            } else {
                transfer::public_transfer(nft, winner);
                break
            }
        };
        addresses_sub_obj::table_keys_clear(
            &mut raffle.addressesSubObjs_table,
            &mut raffle.addressesSubObjs_keys
        );
        emit_nft_raffle_settled(raffle);
    }

    fun getParticipants<T: key+store>(raffle: &NFT_Raffle<T>):vector<address> {
        addresses_sub_obj::table_keys_get_all_addresses(&raffle.addressesSubObjs_table, &raffle.addressesSubObjs_keys)
    }

    fun getWinners<T: key+store>(raffle: &NFT_Raffle<T>):vector<address> {
        raffle.winners
    }
}
