#[test_only]
module raffle::test_coin {
    use raffle::drand_lib::{derive_randomness, verify_drand_signature, safe_selection};
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use std::option::{Self};
    // use sui::sui::SUI;
    use sui::test_utils;
    use sui::transfer;
    
    use std::string::String;
    
    use sui::tx_context::{TxContext};
    use std::vector;
    use std::string::{Self};
    
    use sui::table::{Self, Table};
    struct TEST_COIN has drop {}
    
    fun init(otw: TEST_COIN, ctx: &mut TxContext) {
        let (treasury_cap, metadata) = coin::create_currency(
            otw, 
            2, 
            b"TEST", 
            b"TEST", 
            b"", 
            option::none(), 
            ctx
        );
        transfer::public_share_object(treasury_cap);
        transfer::public_share_object(metadata);
    }
}
