module raffle::signature_randomness_coin_raffle {
    use sui::clock::{Self, Clock};
    use std::debug;
    use raffle::drand_lib::{derive_randomness, verify_drand_signature, safe_selection, get_current_round_by_time};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use std::string::{Self, String};
    use std::ascii::String as ASCIIString;
    use sui::bls12381::bls12381_min_pk_verify;
    use sui::hash::blake2b256;
    use std::hash::{Self};
    use sui::event;
    use std::bcs;
    use std::type_name;
    use sui::object::{Self, UID,ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    
    const EInvalidBlsSig: u64 = 0;

    
    struct CoinRaffleCreated has copy, drop {
        raffle_id: ID,
        raffle_name: String,
        user_seed: vector<u8>,
        time: u64,
        creator: address,
        prizeAmount: u64,
        prizeType: ASCIIString,
    }
    public fun emit_coin_raffle_created<T>(raffle: &Raffle<T>) {
        let raffleType = type_name::into_string(type_name::get<T>());
        let raffleId = *object::borrow_id(raffle);
        let i = 0;
        let participants = getParticipants(raffle);
        event::emit(CoinRaffleCreated {
            raffle_id: raffleId,
            raffle_name: raffle.name,
            user_seed: raffle.user_seed,
            time: raffle.time,
            creator: raffle.creator,
            prizeAmount: balance::value(&raffle.balance),
            prizeType: raffleType,
            }
        );
    }

    // struct CoinRaffleSettled has copy, drop {
    //     raffle_id: ID,
    //     settler: address,
    //     winners: vector<address>,
    // }
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
        user_seed: vector<u8>,
        time: u64,
        host_pub_key: vector<u8>,
        status: u8,
        creator: address,
        settler: address,
        participants: vector<address>,
        participantCount: u64,
        winnerCount: u64,
        winners: vector<address>,
        balance: Balance<T>,
    }
    /// Raffle status
    const IN_PROGRESS: u8 = 0;
    const COMPLETED: u8 = 1;

    
    fun init(_ctx: &mut TxContext) {
    }

    public entry fun create_coin_raffle<T>(
        name: vector<u8>, 
        user_seed: vector<u8>,
        clock: &Clock,
        host_pub_key: vector<u8>,
        participants: vector<address>, 
        winnerCount: u64,
        awardObject: Coin<T>, 
        ctx: &mut TxContext
    ){
        internal_create_coin_raffle(name, user_seed, clock, host_pub_key, participants, winnerCount, awardObject, ctx);
    }
    

    fun internal_create_coin_raffle<T>(
        name: vector<u8>, 
        user_seed: vector<u8>,
        clock: &Clock,
        host_pub_key: vector<u8>,
        participants: vector<address>, 
        winnerCount: u64,
        awardObject: Coin<T>, 
        ctx: &mut TxContext
    ){
        let participantCount = vector::length(&participants);
        assert!(winnerCount <= participantCount, 0);
        let drand_current_round = get_current_round_by_time(clock::timestamp_ms(clock));
        let raffle: Raffle<T> = Raffle {
            id: object::new(ctx),
            name: string::utf8(name),
            user_seed,
            time: clock::timestamp_ms(clock),
            host_pub_key,
            status: IN_PROGRESS,
            creator: tx_context::sender(ctx),
            settler: @0x00,
            participants,
            participantCount,
            winnerCount,
            winners: vector::empty(),
            balance: coin::into_balance<T>(awardObject),
        };
        emit_coin_raffle_created(&raffle);
        transfer::public_share_object(raffle);
    }

    public entry fun verify_sig(
        // raffle: &mut Raffle<T>,
        bls_sig: vector<u8>,
        msg_vec: vector<u8>,
        public_key: vector<u8>,
        ctx: &mut TxContext
    ){
        
        assert!(
            bls12381_min_pk_verify(
                &bls_sig, &public_key, &msg_vec,
            ),
            EInvalidBlsSig
        );
    }

    fun efficient_hash(a: vector<u8>, b: vector<u8>): vector<u8> {
        vector::append(&mut a, b);
        return hash::sha3_256(a)
    }
    
    public entry fun settle_coin_raffle<T>(
        raffle: &mut Raffle<T>,
        bls_sig: vector<u8>,
        ctx: &mut TxContext
    ){
        let message = vector::empty<u8>();
        vector::append(&mut message, raffle.user_seed);
        vector::append(&mut message, bcs::to_bytes(&raffle.time));

        let public_key = raffle.host_pub_key;
        assert!(
            bls12381_min_pk_verify(
                &bls_sig, &public_key, &message,
            ),
            EInvalidBlsSig
        );
        let digest = derive_randomness(bls_sig);
        let random_number = 0;
        let i = 0;

        raffle.status = COMPLETED;
        raffle.settler = tx_context::sender(ctx);
        // // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        
        let participants = raffle.participants;

        let award_per_winner = balance::value(&raffle.balance) / raffle.winnerCount;

        loop{
            i = i+1;
            let length = vector::length(&participants);
            let random_number = safe_selection(length, &digest, random_number);
            let winner = vector::swap_remove(&mut participants, random_number);
            vector::push_back<address>(
                &mut raffle.winners, 
                winner,
            );
            if (i < raffle.winnerCount) {
                transfer::public_transfer(coin::take(&mut raffle.balance, award_per_winner, ctx), winner);
            } else {
                let remain_balance = balance::value(&raffle.balance);
                transfer::public_transfer(coin::take( &mut raffle.balance, remain_balance, ctx), winner);
                break
            }
        };
        raffle.participants = vector::empty();
        // emit_coin_raffle_settled(raffle);
    }

    fun getWinners<T>(raffle: &Raffle<T>):vector<address> {
        raffle.winners
    }
    fun getParticipants<T>(raffle: &Raffle<T>):vector<address> {
        raffle.participants
    }


    #[test]
    fun test_verify_signautre() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        
        
        // SHA3_256("RANDOM")
        let message = x"4022354678f2ab042bd4d3f583c9fee7391826c55d9c8d9f95d09a4f1ae07762";
        let time: u64 = 1687975971000;
        
        vector::append(&mut message, bcs::to_bytes(&time));


        let bls_sig = x"acd9b79159208183f8ac2915896eb51257878a47869c47057e3bd9d37a5db646facf68cabec024d8991106f06d54cf4316cfc1f4c812ffeaaa04642f912e315e36ac12c0c36ef2228ace467de80ad4a00625204ac480843b37be45b3f01a3f5a";
        
        let public_key = x"a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d";

        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            verify_sig(
                bls_sig,
                message,
                public_key,
                test_scenario::ctx(scenario)
            )
        };
        test_scenario::end(scenario_val);
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
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        let winnerCount = 3;
        let totalPrize = 10;
        
        {
            let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
            let participants = vector::empty<address>();
            vector::push_back(&mut participants, user1);
            vector::push_back(&mut participants, user2);
            vector::push_back(&mut participants, user3);
            vector::push_back(&mut participants, user4);
            vector::push_back(&mut participants, user5);
            vector::push_back(&mut participants, user6);
            vector::push_back(&mut participants, user7);
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            
            clock::set_for_testing(&mut clockObj, 1687975971000);
            let user_seed = x"4022354678f2ab042bd4d3f583c9fee7391826c55d9c8d9f95d09a4f1ae07762";
            let host_pub_key = x"a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d";
            create_coin_raffle(b"TEST", user_seed, &clockObj, host_pub_key, participants, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            let signature = x"acd9b79159208183f8ac2915896eb51257878a47869c47057e3bd9d37a5db646facf68cabec024d8991106f06d54cf4316cfc1f4c812ffeaaa04642f912e315e36ac12c0c36ef2228ace467de80ad4a00625204ac480843b37be45b3f01a3f5a";
            settle_coin_raffle(
                &mut raffle, 
                signature,
                test_scenario::ctx(scenario)
            );
            
            let winners = getWinners(&raffle);
            
            // assert!(winnerCount == vector::length(&winners), 0);
            
            test_scenario::return_shared(raffle);
        };
        test_scenario::next_tx(scenario, user1);
        {
            assert!(totalPrize / winnerCount == 3, 0);
            let coin1 = test_scenario::take_from_address<Coin<TEST_COIN>>(scenario, user7);
            assert!(balance::value(coin::balance(&coin1)) == totalPrize / winnerCount, 0);
            test_scenario::return_to_address(user7, coin1);
            let coin2 = test_scenario::take_from_address<Coin<TEST_COIN>>(scenario, user3);
            assert!(balance::value(coin::balance(&coin2)) == totalPrize / winnerCount, 0);
            // debug::print(&balance::value(coin::balance(&coin2)));
            test_scenario::return_to_address(user3, coin2);
            let coin3 = test_scenario::take_from_address<Coin<TEST_COIN>>(scenario, user6);
            assert!(balance::value(coin::balance(&coin3)) == totalPrize - (totalPrize / winnerCount)*(winnerCount - 1), 0);
            test_scenario::return_to_address(user6, coin3);
        };
        
        test_scenario::end(scenario_val);
    }

    #[test]
    fun raffle_10_winner_from_200_participant_without_start_and_settle() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xCAF1;
        
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        let p = 200;
        let winnerCount = 10;
        let totalPrize = 10;
        // let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
        let participants = vector::empty<address>();
        let i = 0;
        loop {
            if (i == p) {
                break
            };
            i = i+1;
            vector::push_back(&mut participants, user1);
        };
        test_scenario::next_tx(scenario, host);
        {
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            let user_seed = x"4022354678f2ab042bd4d3f583c9fee7391826c55d9c8d9f95d09a4f1ae07762";
            let host_pub_key = x"a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d";
            // create_coin_raffle(b"TEST", user_seed, &clockObj, host_pub_key, participants, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            // let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            let signature = x"acd9b79159208183f8ac2915896eb51257878a47869c47057e3bd9d37a5db646facf68cabec024d8991106f06d54cf4316cfc1f4c812ffeaaa04642f912e315e36ac12c0c36ef2228ace467de80ad4a00625204ac480843b37be45b3f01a3f5a";
            // settle_coin_raffle(
            //     &mut raffle, 
            //     signature,
            //     test_scenario::ctx(scenario)
            // );
            
            // let winners = getWinners(&raffle);
            
            // test_scenario::return_shared(raffle);
        };
        
        test_scenario::end(scenario_val);
    }
    
    #[test]
    fun raffle_10_winner_from_200_participant_without_settle() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xCAF1;
        
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        let p = 200;
        let winnerCount = 10;
        let totalPrize = 10;
        let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
        let participants = vector::empty<address>();
        let i = 0;
        loop {
            if (i == p) {
                break
            };
            i = i+1;
            vector::push_back(&mut participants, user1);
        };
        test_scenario::next_tx(scenario, host);
        {
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            let user_seed = x"4022354678f2ab042bd4d3f583c9fee7391826c55d9c8d9f95d09a4f1ae07762";
            let host_pub_key = x"a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d";
            create_coin_raffle(b"TEST", user_seed, &clockObj, host_pub_key, participants, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            let signature = x"acd9b79159208183f8ac2915896eb51257878a47869c47057e3bd9d37a5db646facf68cabec024d8991106f06d54cf4316cfc1f4c812ffeaaa04642f912e315e36ac12c0c36ef2228ace467de80ad4a00625204ac480843b37be45b3f01a3f5a";
            // settle_coin_raffle(
            //     &mut raffle, 
            //     signature,
            //     test_scenario::ctx(scenario)
            // );
            
            // let winners = getWinners(&raffle);
            
            test_scenario::return_shared(raffle);
        };
        
        test_scenario::end(scenario_val);
    }
    
    #[test]
    fun raffle_10_winner_from_200_participant() {
        use raffle::test_coin::{Self, TEST_COIN};
        use sui::test_scenario;
        use sui::balance;
        use std::debug;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xCAF1;
        
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
            // test_coin::init(test_utils::create_one_time_witness<TEST>(), test_scenario::ctx(scenario))
        };

        test_scenario::next_tx(scenario, host);
        let p = 200;
        let winnerCount = 10;
        let totalPrize = 10;
        let coin = coin::from_balance(balance::create_for_testing<TEST_COIN>(totalPrize), test_scenario::ctx(scenario));
        let participants = vector::empty<address>();
        let i = 0;
        loop {
            if (i == p) {
                break
            };
            i = i+1;
            vector::push_back(&mut participants, user1);
        };
        test_scenario::next_tx(scenario, host);
        {
            let clockObj = clock::create_for_testing(test_scenario::ctx(scenario));
            clock::set_for_testing(&mut clockObj, 1687975971000);
            let user_seed = x"4022354678f2ab042bd4d3f583c9fee7391826c55d9c8d9f95d09a4f1ae07762";
            let host_pub_key = x"a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d";
            create_coin_raffle(b"TEST", user_seed, &clockObj, host_pub_key, participants, winnerCount, coin, test_scenario::ctx(scenario));
            clock::destroy_for_testing(clockObj);
        };
        test_scenario::next_tx(scenario, user1);
        {
            let raffle = test_scenario::take_shared<Raffle<TEST_COIN>>(scenario);
            
            let signature = x"acd9b79159208183f8ac2915896eb51257878a47869c47057e3bd9d37a5db646facf68cabec024d8991106f06d54cf4316cfc1f4c812ffeaaa04642f912e315e36ac12c0c36ef2228ace467de80ad4a00625204ac480843b37be45b3f01a3f5a";
            settle_coin_raffle(
                &mut raffle, 
                signature,
                test_scenario::ctx(scenario)
            );
            
            test_scenario::return_shared(raffle);
        };
        
        test_scenario::end(scenario_val);
    }
    
}
