## OURom team ZK-Hackathon submission

For this hackathon, we implemented code for 4 tasks in zk-bridge 1st category:

- RLP Serialization
- ERecover for ECDSA
- Keccak-256
- BSC Header verification

## RLP Serialization

The result inherits a number of of design choices and optimization tricks from [Yi Sun's reference implementation](https://github.com/yi-sun/zk-attestor/blob/master/circuits/rlp.circom). There are a number of key differences:
1. Operates on byte arrays instead of hex arrays.

  This reduces the size of field array to half the size, is more intuitive and drastically reduces the constraint number to half of the original number.

2. Adds support for nested list structure rather than just flat lists.

There are also a number of other optimizations not mentioned. The final result is `rlp.circom`.

## ERecover for ECDSA

The final implementation consists of pure Circom implementation of `ERecover` calcuation and a check on the resulted pubkey.

The main template is `ECDSARecover` in `ecdsa.circom`.

## Keccak-256

The work here is an extention to previous work in [vocdoni/keccak256-circom](https://github.com/vocdoni/keccak256-circom). The repo only has support for fixed-size input that fits in one block (136 * 8 bits), which won't be desirable for most use cases where there will be variable-sized data and has size larger than the limit.

We implemented an enhanced version of keccak that can handle variabled-sized input of data with no max length limit. The main template frunction is `KeccakV` in `keccak.circom`.

## BSC single block header verification

The final task combines the effort from all of the above three tasks. We implemented a bsc single block verifier in Circom that decodes and validates an RLP-encoded BSC block header, and returns the recovered public key which can be further validated to determine if it's in the offical validator set ro not.

The result is `bsc_header.circom`, 