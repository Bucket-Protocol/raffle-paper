// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Example of objects that can be combined to create
/// new objects
module raffle::drand_raffle_with_zero_knowledge_proof {
    use sui::clock::{Self, Clock};
    use raffle::drand_lib::{derive_randomness, verify_drand_signature, safe_selection, get_current_round_by_time};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use std::string::{Self, String};
    use std::ascii::String as ASCIIString;
    use sui::event;
    use std::type_name;
    use sui::object::{Self, UID,ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use raffle::addresses_obj::{Self, AddressesObj};
    use raffle::addresses_sub_obj::{Self, AddressesSubObj};
    use sui::object_table::{Self, ObjectTable};
    use raffle::addresses_hash_proof::{Self, proof_user};
    use sui::vec_map::{Self, VecMap};
    use std::debug;
    const CLAIMED: u64 = 2;
    const UNCLAIMED: u64 = 1;
    

    struct TimeEvent has copy, drop, store { 
        timestamp_ms: u64,
        expect_current_round: u64,
        round_will_use: u64,
    }

    entry fun get_drandlib_round(clock: &Clock) {
        let expect_current_round = get_current_round_by_time(clock::timestamp_ms(clock));
        let round_will_use = expect_current_round + 2;
        event::emit(TimeEvent {
            timestamp_ms: clock::timestamp_ms(clock),
            expect_current_round: expect_current_round,
            round_will_use: round_will_use,
        });
    }
    
    struct CoinRaffleCreated has copy, drop {
        raffle_id: ID,
        raffle_name: String,
        creator: address,
        round: u64,
        participants_count: u64,
        winnerCount: u64,
        prizeAmount: u64,
        prizeType: ASCIIString,
    }
    public fun emit_coin_raffle_created<T>(raffle: &Raffle<T>) {
        let raffleType = type_name::into_string(type_name::get<T>());
        let raffleId = *object::borrow_id(raffle);
        let i = 0;
        event::emit(CoinRaffleCreated {
            raffle_id: raffleId,
            raffle_name: raffle.name,
            creator: raffle.creator,
            round: raffle.round,
            participants_count: raffle.participantCount,
            winnerCount: raffle.winnerCount,
            prizeAmount: balance::value(&raffle.balance),
            prizeType: raffleType,
            }
        );
    }

    struct CoinRaffleSettled has copy, drop {
        raffle_id: ID,
        settler: address,
        winners: vector<address>,
    }
    // public fun emit_coin_raffle_settled<T>(raffle: &Raffle<T>) {
    //     let raffleId = *object::borrow_id(raffle);
    //     event::emit(CoinRaffleSettled {
    //         raffle_id: raffleId,
    //         settler: raffle.settler,
    //         winners: raffle.winners,
    //         }
    //     );
    // }

    struct Raffle <phantom T> has key, store {
        id: UID,
        name: String,
        round: u64,
        status: u8,
        creator: address,
        settler: address,
        participants_Merkle_Root: vector<u8>,
        participantCount: u64,
        winnerCount: u64,
        unclaimedWinnersIndex: vector<u64>,
        claimmedWinnersIndex: vector<u64>,
        claimmedWinners: vector<address>,
        balance: Balance<T>,
    }
    /// Raffle status
    const IN_PROGRESS: u8 = 0;
    const COMPLETED: u8 = 1;

    
    fun init(_ctx: &mut TxContext) {
    }

    public entry fun create_coin_raffle<T>(
        name: vector<u8>, 
        clock: &Clock,
        participants_Merkle_Root: vector<u8>, 
        participantCount: u64,
        winnerCount: u64,
        awardObject: Coin<T>, 
        ctx: &mut TxContext
    ){
        internal_create_coin_raffle(name, clock, participants_Merkle_Root, participantCount, winnerCount, awardObject, ctx);
    }
    

    fun internal_create_coin_raffle<T>(
        name: vector<u8>, 
        clock: &Clock,
        participants_Merkle_Root: vector<u8>, 
        participantCount: u64,
        winnerCount: u64,
        awardObject: Coin<T>, 
        ctx: &mut TxContext
    ){
        let drand_current_round = get_current_round_by_time(clock::timestamp_ms(clock));
        let raffle: Raffle<T> = Raffle {
            id: object::new(ctx),
            name: string::utf8(name),
            round: drand_current_round + 2,
            status: IN_PROGRESS,
            creator: tx_context::sender(ctx),
            settler: @0x00,
            participants_Merkle_Root,
            participantCount,
            winnerCount,
            unclaimedWinnersIndex: vector::empty(),
            claimmedWinnersIndex: vector::empty(),
            claimmedWinners: vector::empty(),
            balance: coin::into_balance<T>(awardObject),
        };
        // emit_coin_raffle_created(&raffle);
        transfer::public_share_object(raffle);
    }

    

    public entry fun settle_coin_raffle<T>(
        raffle: &mut Raffle<T>,
        clock: &Clock,
        drand_sig: vector<u8>,
        drand_prev_sig: vector<u8>,
        ctx: &mut TxContext
    ){
        assert!(raffle.status != COMPLETED, 0);
        if(raffle.creator != tx_context::sender(ctx)){
            let currend_round = get_current_round_by_time(clock::timestamp_ms(clock));
            assert!(currend_round >= raffle.round + 10, 0);
        };
        verify_drand_signature(drand_sig, drand_prev_sig, raffle.round);
        raffle.status = COMPLETED;
        raffle.settler = tx_context::sender(ctx);
        // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        let digest = derive_randomness(drand_sig);
        let random_number = 0;
        let i = 0;

        
        loop{
            i = i+1;
            let length = raffle.participantCount;
            let random_number = safe_selection(length, &digest, random_number);
            
            loop {
                let (contain, index) = vector::index_of(&raffle.unclaimedWinnersIndex, &random_number);
                if(contain){
                    random_number = random_number + 1;
                } else {
                    break
                };
            };
            vector::push_back(&mut raffle.unclaimedWinnersIndex, random_number);
            
            if (i == raffle.winnerCount) {
               break
            }
        };
    }

    public entry fun claim_raffle_reward<T>(
        raffle: &mut Raffle<T>,
        winner_id: u64,
        winner_address: address,
        proofs: vector<vector<u8>>,
        ctx: &mut TxContext
    ){
        let (contained, vector_index) = vector::index_of(&raffle.unclaimedWinnersIndex, &winner_id);
        assert!(contained, 0);
        let valid = proof_user(
            winner_address, 
            winner_id, 
            proofs, 
            raffle.participants_Merkle_Root
        );
        assert!(valid, 0);
        vector::swap_remove(&mut raffle.unclaimedWinnersIndex, vector_index);
        let remained_balance = balance::value(&raffle.balance);
        let balence_to_send = remained_balance / vector::length(&raffle.unclaimedWinnersIndex);
        transfer::public_transfer(coin::take(&mut raffle.balance, balence_to_send, ctx), winner_address);
        vector::push_back(&mut raffle.claimmedWinners, winner_address);
        vector::push_back(&mut raffle.claimmedWinnersIndex, winner_id);
    }



    fun getUnclaimedWinnerIDs<T>(raffle: &Raffle<T>):vector<u64> {
        raffle.unclaimedWinnersIndex
    }
    #[test]
    fun test_raffle() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0x04d626ce8938318165fab01491095329aee67fd017a4a17fe2c981b8a9a569cc;
        
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        let winnerCount = 1;
        let totalPrize = 10;
        let merkle_root = x"bd1d23e6665d7f010df630c66809c19733b79b03e5840a367fa22baf5bed58e4";
        let participantCount = 2;
        
        {
            let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
            
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            
            clock::set_for_testing(&mut clockObj, 1687974871000);
            create_coin_raffle(b"TEST", &clockObj, merkle_root, participantCount, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            assert!(raffle.round == 3084797, 0);
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            
            settle_coin_raffle(
                &mut raffle, 
                &clockObj,
                x"9443823f383e66ab072215da88087c31b129c350f9eebb0651f62da462e19b38d4a35c2f65d825304868d756ed81585016b9e847cf5c51a325e0d02519106ce1999c9292aa8b726609d792a00808dc9e9810ae76e9622e44934d14be32ef9c62",
                x"89aa680c3cde91517dffd9f81bbb5c78baa1c3b4d76b1bfced88e7d8449ff0dc55515e09364db01d05d62bde03a7d08111f95131a7fef2a27e1c8aea8e499189214d38d27deabaf67b35821949fff73b13f0f182588fe1dc73630742bb95ba29", 
                test_scenario::ctx(scenario)
            );
            clock::destroy_for_testing(clockObj);
            let winners = getUnclaimedWinnerIDs(&raffle);
            debug::print(&winners);
            assert!(winnerCount == vector::length(&winners), 0);
            
            test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            let proofs = vector::empty<vector<u8>>();
            let proofs = vector::empty<vector<u8>>();
            vector::push_back(&mut proofs, x"d7029dd97a4e80faa52e93913ab20e9e8b395a749667d8f5efeacf05bb3c9ec3");
            vector::push_back(&mut proofs, x"a78664e853e4a0d260452870ac93bd8bf8f2ffdefea73505c16f7ce55dd72088");
            vector::push_back(&mut proofs, x"eaa13e622a7f2652126114c66ed179d34ac6b91d7aa743712b5edecd3ef7ddb0");
            vector::push_back(&mut proofs, x"e619157d86c8246784e4274463365dc7b73b28aba57a8d6fe836f7195834ec51");
            vector::push_back(&mut proofs, x"a07d80f94badde6d27bc61c3c884b50a6542fd25c0d0c8e00772c7a1f884e94e");
            vector::push_back(&mut proofs, x"eb2d1603e76aead0dda29d0ceda35ec1a0da7a1271a4ba7e4cf0993fb3305160");
            vector::push_back(&mut proofs, x"a047a5b20681c670ffc7b46e9b892fb4b050dc9467af0fa744d52ee770a132f6");
            vector::push_back(&mut proofs, x"0f57ac550dcd8bcab90d573866fbe7604576a8968321d7e722f1f14427dc76f6");
            
            test_scenario::return_shared(raffle);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_raffle_with_claim() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0x04d626ce8938318165fab01491095329aee67fd017a4a17fe2c981b8a9a569cc;
        
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        let winnerCount = 1;
        let totalPrize = 10;
        let merkle_root = x"bd1d23e6665d7f010df630c66809c19733b79b03e5840a367fa22baf5bed58e4";
        let participantCount = 2;
        
        {
            let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
            
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            
            clock::set_for_testing(&mut clockObj, 1687974871000);
            create_coin_raffle(b"TEST", &clockObj, merkle_root, participantCount, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            assert!(raffle.round == 3084797, 0);
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            
            settle_coin_raffle(
                &mut raffle, 
                &clockObj,
                x"9443823f383e66ab072215da88087c31b129c350f9eebb0651f62da462e19b38d4a35c2f65d825304868d756ed81585016b9e847cf5c51a325e0d02519106ce1999c9292aa8b726609d792a00808dc9e9810ae76e9622e44934d14be32ef9c62",
                x"89aa680c3cde91517dffd9f81bbb5c78baa1c3b4d76b1bfced88e7d8449ff0dc55515e09364db01d05d62bde03a7d08111f95131a7fef2a27e1c8aea8e499189214d38d27deabaf67b35821949fff73b13f0f182588fe1dc73630742bb95ba29", 
                test_scenario::ctx(scenario)
            );
            clock::destroy_for_testing(clockObj);
            let winners = getUnclaimedWinnerIDs(&raffle);
            debug::print(&winners);
            assert!(winnerCount == vector::length(&winners), 0);
            
            test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            let proofs = vector::empty<vector<u8>>();
            let proofs = vector::empty<vector<u8>>();
            vector::push_back(&mut proofs, x"d7029dd97a4e80faa52e93913ab20e9e8b395a749667d8f5efeacf05bb3c9ec3");
            vector::push_back(&mut proofs, x"a78664e853e4a0d260452870ac93bd8bf8f2ffdefea73505c16f7ce55dd72088");
            vector::push_back(&mut proofs, x"eaa13e622a7f2652126114c66ed179d34ac6b91d7aa743712b5edecd3ef7ddb0");
            vector::push_back(&mut proofs, x"e619157d86c8246784e4274463365dc7b73b28aba57a8d6fe836f7195834ec51");
            vector::push_back(&mut proofs, x"a07d80f94badde6d27bc61c3c884b50a6542fd25c0d0c8e00772c7a1f884e94e");
            vector::push_back(&mut proofs, x"eb2d1603e76aead0dda29d0ceda35ec1a0da7a1271a4ba7e4cf0993fb3305160");
            vector::push_back(&mut proofs, x"a047a5b20681c670ffc7b46e9b892fb4b050dc9467af0fa744d52ee770a132f6");
            vector::push_back(&mut proofs, x"0f57ac550dcd8bcab90d573866fbe7604576a8968321d7e722f1f14427dc76f6");
            
            let valid = proof_user(
                user1,
                0,
                proofs, 
                raffle.participants_Merkle_Root
            );
            assert!(valid, 0);

            // claim_raffle_reward(&mut raffle, 6, user1, vector::empty(), test_scenario::ctx(scenario));

            test_scenario::return_shared(raffle);
        };

        test_scenario::end(scenario_val);
    }
}
