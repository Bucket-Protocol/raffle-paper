module raffle::signature_randomness_coin_raffle {
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
        participants: vector<address>, 
        winnerCount: u64,
        awardObject: Coin<T>, 
        ctx: &mut TxContext
    ){
        internal_create_coin_raffle(name, user_seed, clock, participants, winnerCount, awardObject, ctx);
    }
    

    fun internal_create_coin_raffle<T>(
        name: vector<u8>, 
        user_seed: u64,
        clock: &Clock,
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
    
    // TODO: Justa
    // 請比照 Coin Flip
    // 讓 Settle 者上傳 Private Key Signature
    // 並且在合約內驗證
    // 之後如果有通過則將簽名進行 Hash 當作隨機數
    // 然後來進行運算把獎金平分給 Winner Count 個 Participants
    // 請也提供 test code，謝謝！
    // 另外如果能提供 JS 部分如何進行簽名的運算就太棒了

    // 你可能還要新增 Public Key 及必要 Library 在這個合約內。

    public entry fun settle_coin_raffle<T>(
        raffle: &mut Raffle<T>,
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
    fun test_raffle() {
        
    }
    
}
