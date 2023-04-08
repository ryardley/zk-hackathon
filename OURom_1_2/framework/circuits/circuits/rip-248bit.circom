pragma circom 2.0.2;
include "./rip.circom"

function byteLenTo248bitLen(byteLen) {
    if ((byteLen % 31) > 0) {
        return byteLen \ 31
    } else {
        return (byteLen \ 31) + 1;
    }
}

template byteTo248bit() {
    signal in[31];
    signal out;

    var sum;
    for (var i = 0; i < 31; i++) {
        sum += in[i] * (1 << (31 - i))
    }
    out <== sum;
}

template _248bitToByte() {
    signal in;
    signal out[31];

    for (var i = 0; i < 31; i++) {
        out[i] <-- (in >> ((31 - i) * 8)) & 0xff
    }

    component byteLimit[31];
    for (var i = 0; i < 31; i++) {
        byteLimit[i] = Num2Bits(8);
        byteLimit[i].in <== out[i];
    }

    component b2n = byteTo248bit();
    for (var i = 0; i < 31; i++) {
        b2n.in[i] <== out[i];
    }
    b2n.out === in;
}

template byteTo248bitArray(maxByteLen) {
    var max248Len = byteLenTo248bitLen(maxByteLen);
    signal in[maxByteLen];
    signal out[max248Len];

    component b2n[max248Len];
    for (var i = 0; i < max248Len; i++) {
        b2n[i] = byteTo248bit();
        for (var j = 0; j < 31; j++) {
            b2n[i].in[j] <== in[i * 31 + j]
        }
        out[i] <== b2n[i].out;
    }
}

template _248bitToByteArray(maxByteLen) {
    var max248Len = byteLenTo248bitLen(maxByteLen);
    signal in[max248Len];
    signal out[maxByteLen];

    component n2b[max248Len];
    for (var i = 0; i < max248Len; i++) {
        n2b[i] = _248bitToByte();
        n2b[i].in <== in[i]
        for (var j = 0; j < 31; j++) {
            out[i * 31 + j] <== n2b[i][j];
        }
    }
}

template RLPDecodeFixedList248Bit() {

}

template RLPDecodeFixedListSelect() {

}

template RLPDecodeString248Bit() {

}

template RLPDecodeList248Bit() {

}
