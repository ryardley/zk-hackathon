pragma circom 2.0.1;

include "../../circuits/rlp.circom";

template TestRLPListPrefix() {
    var maxLen = 100000;
    // Input, RLP representation of the block.
    signal input data[100000]; // 100000 bytes of RLP encodingkk
    signal output prefixLen;
    signal output valueLen;

    component rlpHeader = RLPCheckStringPrefix(maxLen);
    for (var i = 0; i < maxLen; i++) {
        rlpHeader.data[i] <== data[i];
    }
    rlpHeader.start <== 0;
    prefixLen <== rlpHeader.prefixLen;
    valueLen <== rlpHeader.valueLen;
}

component main {public [data]} = TestRLPListPrefix();
