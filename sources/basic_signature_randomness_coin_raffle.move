module raffle::signature_randomness_coin_raffle {
    use sui::clock::{Self, Clock};
    use raffle::drand_lib::{derive_randomness, verify_drand_signature, safe_selection, get_current_round_by_time};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use std::string::{Self, String};
    use std::ascii::String as ASCIIString;
    use sui::bls12381::bls12381_min_pk_verify;
    use sui::hash::blake2b256;
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
        user_seed: u64,
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
        user_seed: u64,
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
        user_seed: u64,
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
        user_seed: u64,
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
    
    // public entry fun settle_coin_raffle<T>(
    //     raffle: &mut Raffle<T>,
    //     bls_sig: vector<u8>,
    //     ctx: &mut TxContext
    // ){
    //     let msg_vec = bcs::to_bytes(&raffle.user_seed);
    //     vector::append(&mut msg_vec, bcs::to_bytes(&raffle.time));
    //     let public_key = raffle.host_pub_key;
    //     assert!(
    //         bls12381_min_pk_verify(
    //             &bls_sig, &public_key, &msg_vec,
    //         ),
    //         EInvalidBlsSig
    //     );

        // raffle.status = COMPLETED;
        // raffle.settler = tx_context::sender(ctx);
        // // // The randomness is derived from drand_sig by passing it through sha2_256 to make it uniform.
        // // let digest = derive_randomness(drand_sig);
        // // let random_number = 0;
        // // let i = 0;

        // let participants = raffle.participants;

        // let award_per_winner = balance::value(&raffle.balance) / raffle.winnerCount;

        // loop{
        //     i = i+1;
        //     let length = vector::length(&participants);
        //     let random_number = safe_selection(length, &digest, random_number);
        //     let winner = vector::swap_remove(&mut participants, random_number);
        //     vector::push_back<address>(
        //         &mut raffle.winners, 
        //         winner,
        //     );
        //     if (i < raffle.winnerCount) {
        //         transfer::public_transfer(coin::take(&mut raffle.balance, award_per_winner, ctx), winner);
        //     } else {
        //         let remain_balance = balance::value(&raffle.balance);
        //         transfer::public_transfer(coin::take( &mut raffle.balance, remain_balance, ctx), winner);
        //         break
        //     }
        // };
        // raffle.participants = vector::empty();
        // // emit_coin_raffle_settled(raffle);
    // }

    fun getWinners<T>(raffle: &Raffle<T>):vector<address> {
        raffle.winners
    }
    fun getParticipants<T>(raffle: &Raffle<T>):vector<address> {
        raffle.participants
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
        let bls_sig = x"a3a599fd887de55eef7b3f90d01784a84f777076c02aff2c29036293e0eee3822a230b6274cc66d734bdfeda3e83a01c0360c3e391892f9de37b630a02435be8f7d4b13a711f86b3f1ad3ce090899165513f3a6facd2f1348e4911cc758a2cb8";
        let message = x"7902030405";
        let public_key = x"a7e75af9dd4d868a41ad2f5a5b021d653e31084261724fb40ae2f1b1c31c778d3b9464502d599cf6720723ec5c68b59d";
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
    
}
