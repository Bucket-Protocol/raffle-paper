/// Helper module for working with drand outputs.
/// Currently works with chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
///
/// See examples in drand_based_lottery.move.
///
module raffle::drand_lib {
    use sui::clock::{Self, Clock};
    use sui::event;
    use std::hash::sha2_256;
    use std::vector;

    use sui::bls12381;

    /// Error codes
    const EInvalidRndLength: u64 = 0;
    const EInvalidProof: u64 = 1;

    /// The genesis time of chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
    const GENESIS: u64 = 1595431050;
    /// The public key of chain 8990e7a9aaed2ffed73dbd7092123d6f289930540d7651336225dc172e51b2ce.
    const DRAND_PK: vector<u8> =
        x"868f005eb8e6e4ca0a47c8a77ceaa5309a47978a7c71bc5cce96366b5d7a569937c529eeda66c7293784a9402801af31";

    const DRAND_Initial_Start_Time: u64 = 1595431021000;


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
    /// Check that a given epoch time has passed by verifying a drand signature from a later time.
    /// round must be at least (epoch_time - GENESIS)/30 + 1).
    public fun verify_time_has_passed(epoch_time: u64, sig: vector<u8>, prev_sig: vector<u8>, round: u64) {
        assert!(epoch_time <= GENESIS + 30 * (round - 1), EInvalidProof);
        verify_drand_signature(sig, prev_sig, round);
    }

    public fun get_current_round_by_time(timestamp_ms: u64): u64{
        (timestamp_ms - DRAND_Initial_Start_Time)/30000
    }
    /// Check a drand output.
    public entry fun just_check_drand(drand_sig: vector<u8>, drand_prev_sig: vector<u8>, round: u64) {
        verify_drand_signature(drand_sig, drand_prev_sig, round);
    }
    public fun verify_drand_signature(sig: vector<u8>, prev_sig: vector<u8>, round: u64) {

        // debug::print( &sig);
        // debug::print(&prev_sig);
        // Convert round to a byte array in big-endian order.
        let round_bytes: vector<u8> = vector[0, 0, 0, 0, 0, 0, 0, 0];
        let i = 7;
        while (i > 0) {
            let curr_byte = round % 0x100;
            let curr_element = vector::borrow_mut(&mut round_bytes, i);
            *curr_element = (curr_byte as u8);
            round = round >> 8;
            i = i - 1;
        };

        // Compute sha256(prev_sig, round_bytes).
        vector::append(&mut prev_sig, round_bytes);
        let digest = sha2_256(prev_sig);
        // Verify the signature on the hash.
        
        bls12381::bls12381_min_pk_verify(&sig, &DRAND_PK, &digest);
        // debug::print(&res);
        
        assert!(bls12381::bls12381_min_pk_verify(&sig, &DRAND_PK, &digest), EInvalidProof);
    }

    /// Derive a uniform vector from a drand signature.
    public fun derive_randomness(drand_sig: vector<u8>): vector<u8> {
        sha2_256(drand_sig)
    }

    // Converts the first 16 bytes of rnd to a u128 number and outputs its modulo with input n.
    // Since n is u64, the output is at most 2^{-64} biased assuming rnd is uniformly random.
    public fun safe_selection(n: u64, rnd: &vector<u8>): u64 {
        assert!(vector::length(rnd) >= 16, EInvalidRndLength);
        let m: u128 = 0;
        let i = 0;
        while (i < 16) {
            m = m << 8;
            let curr_byte = *vector::borrow(rnd, i);
            m = m + (curr_byte as u128);
            i = i + 1;
        };
        let n_128 = (n as u128);
        let module_128  = m % n_128;
        let res = (module_128 as u64);
        res
    }
    #[test]
    fun test_init() {
        use sui::test_scenario;
        // create test addresses representing users
        let admin = @0xad;
        let host = @0xac;
        let user1 = @0xCAFE;
        let user2 = @0xCAFF;
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        
        {
            verify_drand_signature(
            x"9443823f383e66ab072215da88087c31b129c350f9eebb0651f62da462e19b38d4a35c2f65d825304868d756ed81585016b9e847cf5c51a325e0d02519106ce1999c9292aa8b726609d792a00808dc9e9810ae76e9622e44934d14be32ef9c62",
            x"89aa680c3cde91517dffd9f81bbb5c78baa1c3b4d76b1bfced88e7d8449ff0dc55515e09364db01d05d62bde03a7d08111f95131a7fef2a27e1c8aea8e499189214d38d27deabaf67b35821949fff73b13f0f182588fe1dc73630742bb95ba29", 
            3084797);
            
        };
        test_scenario::end(scenario_val);
    }
}
