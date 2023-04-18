## OURoc team ZK-Hackathon submission

For this hackathon, we implemented code for 4 tasks in zk-Brige/zk-Circuit Circuit category:

- RLP Serialization
- ERecover for ECDSA
- Keccak-256
- BSC Header verification

All the implementations are in Circom language.

## RLP Serialization

The result inherits a number of of design choices and optimization tricks from [Yi Sun's reference implementation](https://github.com/yi-sun/zk-attestor/blob/master/circuits/rlp.circom). There are a number of key differences:
1. Operates on byte arrays instead of hex arrays.

  This reduces the size of field array to half the size, is more intuitive and drastically reduces the constraint number to half of the original number.

2. Adds support for nested list structure rather than just flat lists.

We also did a number of other optimization techniques. The final result is `rlp.circom`.

## ERecover for ECDSA

The final implementation consists of pure Circom implementation of `ERecover` calcuation and a check on the resulted pubkey.

Mainly it implements the logic of recovring public key from r, s, v and then use constraints to verify that public key against the signature. This is because the logic of recoving the public key is more costly than the logic to verify it against the signature.

The main template is `ECDSARecover` in `ecdsa.circom`.

## Keccak-256

The work here is based on previous work in [vocdoni/keccak256-circom](https://github.com/vocdoni/keccak256-circom). The repo only had support for fixed-size input with a maximum length of one block (136 * 8 bits). This won't be desirable for most use cases where there will be variable-sized data and has size larger than the limit.

We implemented an enhanced version of keccak that can handle variabled-sized input of data with no max length limit. The main template frunction is `KeccakV` in `keccak.circom`. This enables the circuit to be applicable for a lot more use cases.

## BSC single block header verification

The final task combines the effort from all of the above three tasks. We implemented a bsc single block verifier in Circom that decodes and validates an RLP-encoded BSC block header, and returns the recovered public key which can be further validated on-chain to determine if the block is signed by a valid validator.

The result is `bsc_header.circom`.

## Note for running the npm test

Compiling circuit for some of the projects would fail because the stderr (compiler warnings) size exceeds the default maximum size. There's no way to fix it with the current `wasm_tester` version. A workaround would be to update the line in `node_modules\circom_tester\wasm\tester.js` that invokes `circom` in to something like `b = await exec("circom " + flags + fileName, {maxBuffer: 1024*1024*1024});`. Or we could manually compile the circuit to a folder and specify that folder in the test.
