# Building Random, Fair, and Verifiable Games on Blockchain. Raffle smart contract designs on Sui Network

Source code of the paper at https://arxiv.org/abs/2310.12305

# How to use?
1. Install Sui Cli following the Sui Official Guide https://docs.sui.io/build/install#install-sui-binaries

2. Calculate transaction fee by the following command:

```
sui move test --ignore_compile_warnings -s
```


- For Raffle except Zero Knowledge Proof:
  - the test pipeline `raffle_10_winner_from_200_participant_*` is the target we test.
  - `*_without_settle` is the pipeline without executing settle function.
  - `*_without_start_and_settle` is the pipeline without executing start and settle function.
  - Use the above two to calculate start and settle fee respectively.
- For Raffle with Zero Knowledge Proof:
  - - the test pipeline `test_raffle_*` is the target we test.
  - `*_without_start_settle_claim`is the pipeline without executing anyting (only set up fee).
  - `*_with_start_without_settle_claim ` is the pipeline without executing settle and claim function.
  - `*_with_start_settle_without_claim` is the pipeline executing start and settle of the raffle without executing the claiming function.
  - `*_with_start_settle_claim` is the pipeline executing start and settle of the raffle with one round of claiming function.
  - Use the above pipelines to calculate start, settle, and claim fee respectively.


 # References

```
@misc{chen2023building,
      title={Building Random, Fair, and Verifiable Games on Blockchain. Raffle smart contract designs on Sui Network}, 
      author={Eason Chen and Justa Liang and Ray Huang and Pierce Hung and Damien Chen and Ashley Hsu and Konstantinos Chalkias and Stefanos Pleros},
      year={2023},
      eprint={2310.12305},
      archivePrefix={arXiv},
      primaryClass={cs.CR}
}
```
