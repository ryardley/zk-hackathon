// Keccak256 hash function (ethereum version).
// For LICENSE check https://github.com/vocdoni/keccak256-circom/blob/master/LICENSE

pragma circom 2.0.0;

include "./utils.circom";
include "./permutations.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/switcher.circom";

template Pad(nBits) {
    signal input in[nBits];

    var blockSize=136*8;
    signal output out[blockSize];
    signal out2[blockSize];

    var i;

    for (i=0; i<nBits; i++) {
        out2[i] <== in[i];
    }
    var domain = 0x01;
    for (i=0; i<8; i++) {
        out2[nBits+i] <== (domain >> i) & 1;
    }
    for (i=nBits+8; i<blockSize; i++) {
        out2[i] <== 0;
    }
    component aux = OrArray(8);
    for (i=0; i<8; i++) {
        aux.a[i] <== out2[blockSize-8+i];
        aux.b[i] <== (0x80 >> i) & 1;
    }
    for (i=0; i<8; i++) {
        out[blockSize-8+i] <== aux.out[i];
    }
    for (i=0; i<blockSize-8; i++) {
        out[i]<==out2[i];
    }
}

template PadV() {
    var blockSize=136*8;

    signal input in[blockSize];
    signal input len;
    signal output out[blockSize];
    assert(len % 8 == 0);
    assert(len <= blockSize);

    component is_eq[blockSize-1];
    component less_than[blockSize-1];
    component sw1[blockSize-1];
    component sw2[blockSize-1];
    for (var i = 0; i < blockSize-1; i++) {
        is_eq[i] = IsEqual();
        is_eq[i].in[0] <== i;
        is_eq[i].in[1] <== len;
        sw1[i] = Switcher();
        sw1[i].L <== in[i];
        sw1[i].R <== 1;
        sw1[i].sel <== is_eq[i].out;

        less_than[i] = LessThan(num_bits(blockSize));
        less_than[i].in[0] <== i;
        less_than[i].in[1] <== len + 1; // for i <= len, we'd like to keep the original input (with the padded 1)
        sw2[i] = Switcher();
        sw2[i].L <== sw1[i].outL;
        sw2[i].R <== 0;
        sw2[i].sel <== 1 - less_than[i].out;

        out[i] <== sw2[i].outL;
    }
    out[blockSize-1] <== 1;
}

template KeccakfRound(r) {
    signal input in[25*64];
    signal output out[25*64];
    var i;

    component theta = Theta();
    component rhopi = RhoPi();
    component chi = Chi();
    component iota = Iota(r);

    for (i=0; i<25*64; i++) {
        theta.in[i] <== in[i];
    }
    for (i=0; i<25*64; i++) {
        rhopi.in[i] <== theta.out[i];
    }
    for (i=0; i<25*64; i++) {
        chi.in[i] <== rhopi.out[i];
    }
    for (i=0; i<25*64; i++) {
        iota.in[i] <== chi.out[i];
    }
    for (i=0; i<25*64; i++) {
        out[i] <== iota.out[i];
    }
}

template Absorb() {
    var blockSizeBytes=136;

    signal input s[25*64];
    signal input block[blockSizeBytes*8];
    signal output out[25*64];
    var i;
    var j;

    component aux[blockSizeBytes/8];
    component newS = Keccakf();

    for (i=0; i<blockSizeBytes/8; i++) {
        aux[i] = XorArray(64);
        for (j=0; j<64; j++) {
            aux[i].a[j] <== s[i*64+j];
            aux[i].b[j] <== block[i*64+j];
        }
        for (j=0; j<64; j++) {
            newS.in[i*64+j] <== aux[i].out[j];
        }
    }
    // fill the missing s that was not covered by the loop over
    // blockSizeBytes/8
    for (i=(blockSizeBytes/8)*64; i<25*64; i++) {
            newS.in[i] <== s[i];
    }
    for (i=0; i<25*64; i++) {
        out[i] <== newS.out[i];
    }
}

template Final(nBits) {
    signal input in[nBits];
    signal output out[25*64];
    var blockSize=136*8;
    var i;

    // pad
    component pad = Pad(nBits);
    for (i=0; i<nBits; i++) {
        pad.in[i] <== in[i];
    }
    // absorb
    component abs = Absorb();
    for (i=0; i<blockSize; i++) {
        abs.block[i] <== pad.out[i];
    }
    for (i=0; i<25*64; i++) {
        abs.s[i] <== 0;
    }
    for (i=0; i<25*64; i++) {
        out[i] <== abs.out[i];
    }
}

template Squeeze(nBits) {
    signal input s[25*64];
    signal output out[nBits];
    var i;
    var j;

    for (i=0; i<25; i++) {
        for (j=0; j<64; j++) {
            if (i*64+j<nBits) {
                out[i*64+j] <== s[i*64+j];
            }
        }
    }
}

template Keccakf() {
    signal input in[25*64];
    signal output out[25*64];
    var i;
    var j;

    // 24 rounds
    component round[24];
    signal midRound[24*25*64];
    for (i=0; i<24; i++) {
        round[i] = KeccakfRound(i);
        if (i==0) {
            for (j=0; j<25*64; j++) {
                midRound[j] <== in[j];
            }
        }
        for (j=0; j<25*64; j++) {
            round[i].in[j] <== midRound[i*25*64+j];
        }
        if (i<23) {
            for (j=0; j<25*64; j++) {
                midRound[(i+1)*25*64+j] <== round[i].out[j];
            }
        }
    }

    for (i=0; i<25*64; i++) {
        out[i] <== round[23].out[i];
    }
}

template Keccak(nBitsIn, nBitsOut) {
    assert(nBitsIn < 136*8);
    signal input in[nBitsIn];
    signal output out[nBitsOut];
    var i;

    component f = Final(nBitsIn);
    for (i=0; i<nBitsIn; i++) {
        f.in[i] <== in[i];
    }
    component squeeze = Squeeze(nBitsOut);
    for (i=0; i<25*64; i++) {
        squeeze.s[i] <== f.out[i];
    }
    for (i=0; i<nBitsOut; i++) {
        out[i] <== squeeze.out[i];
    }
}

template KeccakLongInput(nBitsIn, nBitsOut) {
    var nBlocks = (nBitsIn + 136*8 - 1) / (136*8);
    signal input in[nBitsIn];
    signal input length;
    signal output out[nBitsOut];
    var i;

    var absorbBlocks = nBlocks - 1;
    var finalS[25*64];
    component absorbs[absorbBlocks];
    if (absorbBlocks == 0) {
        for (var i = 0; i < 25*64; i++) {
            finalS[i] = 0;
        }
    } else {
        for (var i = 0; i < absorbBlocks; i++) {
            absorbs[i] = Absorb();
            for (var j = 0; j < 136*8; j++) {
                absorbs[i].block[j] <== in[i*136*8 + j];
            }
            for (var j = 0; j < 25*64; j++) {
                absorbs[i].s[j] <== (i == 0) ? 0 : absorbs[i-1].out[j];
            }
        }
    }
    component absorber[nBlocks-1];
    for (i = 0; i < nBlocks-1; i++) {
        absorber[i] = Absorb();

        for (var j = 0; j < 136*8; j++) {
            if (i*136*8 + j < length) {
                absorber[i].block[j] <== in[i*136*8 + j];
            } else {
                absorber[i].block[j] <== 0;
            }
        }

        for (var j = 0; j < 25*64; j++) {
            // absorber[i].s[j] <== (i == 0) ? state[j] : absorber[i-1].out[j];
        }
    }

    // component final = FinalV();

    // component squeeze = Squeeze(nBitsOut);
    // for (i = 0; i < 25*64; i++) {
    //     squeeze.s[i] <== absorber[nBlocks-1].out[i];
    // }
    // for (i = 0; i < nBitsOut; i++) {
    //     out[i] <== squeeze.out[i];
    // }
}
