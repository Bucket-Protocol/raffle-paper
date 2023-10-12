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

        let remained_balance = balance::value(&raffle.balance);
        let balence_to_send = remained_balance / vector::length(&raffle.unclaimedWinnersIndex);
        transfer::public_transfer(coin::take(&mut raffle.balance, balence_to_send, ctx), winner_address);
        vector::swap_remove(&mut raffle.unclaimedWinnersIndex, vector_index);
        vector::push_back(&mut raffle.claimmedWinners, winner_address);
        vector::push_back(&mut raffle.claimmedWinnersIndex, winner_id);
    }



    fun getUnclaimedWinnerIDs<T>(raffle: &Raffle<T>):vector<u64> {
        raffle.unclaimedWinnersIndex
    }
    
    
    #[test]
    fun test_raffle_without_start_settle_claim() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xcba2aa3c7ee3f3f6580e78ba0008577867e20784bc5b3ad8f76db0ad4176f0e4;
        
        let winnerCount = 1;
        let totalPrize = 10;

        let user1_index = 0;
        let merkle_root = x"8714127bd7b54f7cd362ea56141fcf741c9937fb399feec150014511d68b715f";
        let participantCount = 2; // set it to 2 for testing, so the id 0 will be the winner.
        let proofs = vector::empty<vector<u8>>();
        vector::push_back(&mut proofs, x"b14995a1c47168773d46d4a809e980182dda361e26ed441d7814f938019375af");
        vector::push_back(&mut proofs, x"b4624a82b5742fb96be8f3e644274c8059fdf9bf03b6894264f2338858a20dc6");
        vector::push_back(&mut proofs, x"8d2d65241d70edef4ca8d02b21e739f866475e028822f0083865f2f341db53ce");
        vector::push_back(&mut proofs, x"86794d761065aec1cfcfced7b680eccf8ace01e27875d427d9a37064a8eec7e1");
        vector::push_back(&mut proofs, x"3a539cde95b655a045994ffa3f55de7ec9a3746d5019e735a6370381b5c8e1e3");
        vector::push_back(&mut proofs, x"c5811e5652ad00e70c90c5939c5b13b588362066f889419950d0ab870ec76231");
        vector::push_back(&mut proofs, x"d5dfb532a73d5d1372e9a069028681b8975538395ea81705e39c7a64cb8af9fc");
        vector::push_back(&mut proofs, x"ccd7d991d797c2d306c83a6837b9af87a78734ec35a8568382d361a7e3c75aee");
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        
        {
            // let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
            
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            
            clock::set_for_testing(&mut clockObj, 1687974871000);
            // create_coin_raffle(b"TEST", &clockObj, merkle_root, participantCount, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            // let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            
            // settle_coin_raffle(
            //     &mut raffle, 
            //     &clockObj,
            //     x"9443823f383e66ab072215da88087c31b129c350f9eebb0651f62da462e19b38d4a35c2f65d825304868d756ed81585016b9e847cf5c51a325e0d02519106ce1999c9292aa8b726609d792a00808dc9e9810ae76e9622e44934d14be32ef9c62",
            //     x"89aa680c3cde91517dffd9f81bbb5c78baa1c3b4d76b1bfced88e7d8449ff0dc55515e09364db01d05d62bde03a7d08111f95131a7fef2a27e1c8aea8e499189214d38d27deabaf67b35821949fff73b13f0f182588fe1dc73630742bb95ba29", 
            //     test_scenario::ctx(scenario)
            // );
            clock::destroy_for_testing(clockObj);
            
            // test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            // let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            // claim_raffle_reward(&mut raffle, user1_index, user1, proofs, test_scenario::ctx(scenario));

            // test_scenario::return_shared(raffle);
        };

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_raffle_with_start_without_settle_claim() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xcba2aa3c7ee3f3f6580e78ba0008577867e20784bc5b3ad8f76db0ad4176f0e4;
        
        let winnerCount = 1;
        let totalPrize = 10;

        let user1_index = 0;
        let merkle_root = x"8714127bd7b54f7cd362ea56141fcf741c9937fb399feec150014511d68b715f";
        let participantCount = 2; // set it to 2 for testing, so the id 0 will be the winner.
        let proofs = vector::empty<vector<u8>>();
        vector::push_back(&mut proofs, x"b14995a1c47168773d46d4a809e980182dda361e26ed441d7814f938019375af");
        vector::push_back(&mut proofs, x"b4624a82b5742fb96be8f3e644274c8059fdf9bf03b6894264f2338858a20dc6");
        vector::push_back(&mut proofs, x"8d2d65241d70edef4ca8d02b21e739f866475e028822f0083865f2f341db53ce");
        vector::push_back(&mut proofs, x"86794d761065aec1cfcfced7b680eccf8ace01e27875d427d9a37064a8eec7e1");
        vector::push_back(&mut proofs, x"3a539cde95b655a045994ffa3f55de7ec9a3746d5019e735a6370381b5c8e1e3");
        vector::push_back(&mut proofs, x"c5811e5652ad00e70c90c5939c5b13b588362066f889419950d0ab870ec76231");
        vector::push_back(&mut proofs, x"d5dfb532a73d5d1372e9a069028681b8975538395ea81705e39c7a64cb8af9fc");
        vector::push_back(&mut proofs, x"ccd7d991d797c2d306c83a6837b9af87a78734ec35a8568382d361a7e3c75aee");
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        
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
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            
            // settle_coin_raffle(
            //     &mut raffle, 
            //     &clockObj,
            //     x"9443823f383e66ab072215da88087c31b129c350f9eebb0651f62da462e19b38d4a35c2f65d825304868d756ed81585016b9e847cf5c51a325e0d02519106ce1999c9292aa8b726609d792a00808dc9e9810ae76e9622e44934d14be32ef9c62",
            //     x"89aa680c3cde91517dffd9f81bbb5c78baa1c3b4d76b1bfced88e7d8449ff0dc55515e09364db01d05d62bde03a7d08111f95131a7fef2a27e1c8aea8e499189214d38d27deabaf67b35821949fff73b13f0f182588fe1dc73630742bb95ba29", 
            //     test_scenario::ctx(scenario)
            // );
            clock::destroy_for_testing(clockObj);
            
            test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            // claim_raffle_reward(&mut raffle, user1_index, user1, proofs, test_scenario::ctx(scenario));

            test_scenario::return_shared(raffle);
        };

        test_scenario::end(scenario_val);
    }
    


    #[test]
    fun test_raffle_with_start_settle_without_claim() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xcba2aa3c7ee3f3f6580e78ba0008577867e20784bc5b3ad8f76db0ad4176f0e4;
        
        let winnerCount = 1;
        let totalPrize = 10;

        let user1_index = 0;
        let merkle_root = x"8714127bd7b54f7cd362ea56141fcf741c9937fb399feec150014511d68b715f";
        let participantCount = 2; // set it to 2 for testing, so the id 0 will be the winner.
        let proofs = vector::empty<vector<u8>>();
        vector::push_back(&mut proofs, x"b14995a1c47168773d46d4a809e980182dda361e26ed441d7814f938019375af");
        vector::push_back(&mut proofs, x"b4624a82b5742fb96be8f3e644274c8059fdf9bf03b6894264f2338858a20dc6");
        vector::push_back(&mut proofs, x"8d2d65241d70edef4ca8d02b21e739f866475e028822f0083865f2f341db53ce");
        vector::push_back(&mut proofs, x"86794d761065aec1cfcfced7b680eccf8ace01e27875d427d9a37064a8eec7e1");
        vector::push_back(&mut proofs, x"3a539cde95b655a045994ffa3f55de7ec9a3746d5019e735a6370381b5c8e1e3");
        vector::push_back(&mut proofs, x"c5811e5652ad00e70c90c5939c5b13b588362066f889419950d0ab870ec76231");
        vector::push_back(&mut proofs, x"d5dfb532a73d5d1372e9a069028681b8975538395ea81705e39c7a64cb8af9fc");
        vector::push_back(&mut proofs, x"ccd7d991d797c2d306c83a6837b9af87a78734ec35a8568382d361a7e3c75aee");
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        
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
            
            test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            // claim_raffle_reward(&mut raffle, user1_index, user1, proofs, test_scenario::ctx(scenario));

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
        let user1 = @0xcba2aa3c7ee3f3f6580e78ba0008577867e20784bc5b3ad8f76db0ad4176f0e4;
        
        let winnerCount = 1;
        let totalPrize = 10;

        let user1_index = 0;
        let merkle_root = x"8714127bd7b54f7cd362ea56141fcf741c9937fb399feec150014511d68b715f";
        let participantCount = 2; // set it to 2 for testing, so the id 0 will be the winner.
        let proofs = vector::empty<vector<u8>>();
        vector::push_back(&mut proofs, x"b14995a1c47168773d46d4a809e980182dda361e26ed441d7814f938019375af");
        vector::push_back(&mut proofs, x"b4624a82b5742fb96be8f3e644274c8059fdf9bf03b6894264f2338858a20dc6");
        vector::push_back(&mut proofs, x"8d2d65241d70edef4ca8d02b21e739f866475e028822f0083865f2f341db53ce");
        vector::push_back(&mut proofs, x"86794d761065aec1cfcfced7b680eccf8ace01e27875d427d9a37064a8eec7e1");
        vector::push_back(&mut proofs, x"3a539cde95b655a045994ffa3f55de7ec9a3746d5019e735a6370381b5c8e1e3");
        vector::push_back(&mut proofs, x"c5811e5652ad00e70c90c5939c5b13b588362066f889419950d0ab870ec76231");
        vector::push_back(&mut proofs, x"d5dfb532a73d5d1372e9a069028681b8975538395ea81705e39c7a64cb8af9fc");
        vector::push_back(&mut proofs, x"ccd7d991d797c2d306c83a6837b9af87a78734ec35a8568382d361a7e3c75aee");
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        
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
            
            test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            claim_raffle_reward(&mut raffle, user1_index, user1, proofs, test_scenario::ctx(scenario));

            test_scenario::return_shared(raffle);
        };

        test_scenario::end(scenario_val);
    }
}
