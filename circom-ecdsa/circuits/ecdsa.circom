pragma circom 2.0.2;

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/multiplexer.circom";
include "../node_modules/circomlib/circuits/mux1.circom";

include "bigint.circom";
include "secp256k1.circom";
include "bigint_func.circom";
include "ecdsa_func.circom";
include "secp256k1_func.circom";

// keys are encoded as (x, y) pairs with each coordinate being
// encoded with k registers of n bits each
template ECDSAPrivToPub(n, k) {
    var stride = 8;
    signal input privkey[k];
    signal output pubkey[2][k];

    component n2b[k];
    for (var i = 0; i < k; i++) {
        n2b[i] = Num2Bits(n);
        n2b[i].in <== privkey[i];
    }

    var num_strides = div_ceil(n * k, stride);
    // power[i][j] contains: [j * (1 << stride * i) * G] for 1 <= j < (1 << stride)
    var powers[num_strides][2 ** stride][2][k];
    powers = get_g_pow_stride8_table(n, k);

    // contains a dummy point G * 2 ** 255 to stand in when we are adding 0
    // this point is sometimes an input into AddUnequal, so it must be guaranteed
    // to never equal any possible partial sum that we might get
    var dummyHolder[2][100] = get_dummy_point(n, k);
    var dummy[2][k];
    for (var i = 0; i < k; i++) dummy[0][i] = dummyHolder[0][i];
    for (var i = 0; i < k; i++) dummy[1][i] = dummyHolder[1][i];

    // selector[i] contains a value in [0, ..., 2**i - 1]
    component selectors[num_strides];
    for (var i = 0; i < num_strides; i++) {
        selectors[i] = Bits2Num(stride);
        for (var j = 0; j < stride; j++) {
            var bit_idx1 = (i * stride + j) \ n;
            var bit_idx2 = (i * stride + j) % n;
            if (bit_idx1 < k) {
                selectors[i].in[j] <== n2b[bit_idx1].out[bit_idx2];
            } else {
                selectors[i].in[j] <== 0;
            }
        }
    }

    // multiplexers[i][l].out will be the coordinates of:
    // selectors[i].out * (2 ** (i * stride)) * G    if selectors[i].out is non-zero
    // (2 ** 255) * G                                if selectors[i].out is zero
    component multiplexers[num_strides][2];
    // select from k-register outputs using a 2 ** stride bit selector
    for (var i = 0; i < num_strides; i++) {
        for (var l = 0; l < 2; l++) {
            multiplexers[i][l] = Multiplexer(k, (1 << stride));
            multiplexers[i][l].sel <== selectors[i].out;
            for (var idx = 0; idx < k; idx++) {
                multiplexers[i][l].inp[0][idx] <== dummy[l][idx];
                for (var j = 1; j < (1 << stride); j++) {
                    multiplexers[i][l].inp[j][idx] <== powers[i][j][l][idx];
                }
            }
        }
    }

    component iszero[num_strides];
    for (var i = 0; i < num_strides; i++) {
        iszero[i] = IsZero();
        iszero[i].in <== selectors[i].out;
    }

    // has_prev_nonzero[i] = 1 if at least one of the selections in privkey up to stride i is non-zero
    component has_prev_nonzero[num_strides];
    has_prev_nonzero[0] = OR();
    has_prev_nonzero[0].a <== 0;
    has_prev_nonzero[0].b <== 1 - iszero[0].out;
    for (var i = 1; i < num_strides; i++) {
        has_prev_nonzero[i] = OR();
        has_prev_nonzero[i].a <== has_prev_nonzero[i - 1].out;
        has_prev_nonzero[i].b <== 1 - iszero[i].out;
    }

    signal partial[num_strides][2][k];
    for (var idx = 0; idx < k; idx++) {
        for (var l = 0; l < 2; l++) {
            partial[0][l][idx] <== multiplexers[0][l].out[idx];
        }
    }

    component adders[num_strides - 1];
    signal intermed1[num_strides - 1][2][k];
    signal intermed2[num_strides - 1][2][k];
    for (var i = 1; i < num_strides; i++) {
        adders[i - 1] = Secp256k1AddUnequal(n, k);
        for (var idx = 0; idx < k; idx++) {
            for (var l = 0; l < 2; l++) {
                adders[i - 1].a[l][idx] <== partial[i - 1][l][idx];
                adders[i - 1].b[l][idx] <== multiplexers[i][l].out[idx];
            }
        }

        // partial[i] = has_prev_nonzero[i - 1] * ((1 - iszero[i]) * adders[i - 1].out + iszero[i] * partial[i - 1][0][idx])
        //              + (1 - has_prev_nonzero[i - 1]) * (1 - iszero[i]) * multiplexers[i]
        for (var idx = 0; idx < k; idx++) {
            for (var l = 0; l < 2; l++) {
                intermed1[i - 1][l][idx] <== iszero[i].out * (partial[i - 1][l][idx] - adders[i - 1].out[l][idx]) + adders[i - 1].out[l][idx];
                intermed2[i - 1][l][idx] <== multiplexers[i][l].out[idx] - iszero[i].out * multiplexers[i][l].out[idx];
                partial[i][l][idx] <== has_prev_nonzero[i - 1].out * (intermed1[i - 1][l][idx] - intermed2[i - 1][l][idx]) + intermed2[i - 1][l][idx];
            }
        }
    }

    for (var i = 0; i < k; i++) {
        for (var l = 0; l < 2; l++) {
            pubkey[l][i] <== partial[num_strides - 1][l][i];
        }
    }
}

// r, s, msghash, and pubkey have coordinates
// encoded with k registers of n bits each
// signature is (r, s)
// Does not check that pubkey is valid
template ECDSAVerifyNoPubkeyCheck(n, k) {
    assert(k >= 2);
    assert(k <= 100);

    signal input r[k];
    signal input s[k];
    signal input msghash[k];
    signal input pubkey[2][k];

    signal output result;

    var p[100] = get_secp256k1_prime(n, k);
    var order[100] = get_secp256k1_order(n, k);

    // compute multiplicative inverse of s mod n
    var sinv_comp[100] = mod_inv(n, k, s, order);
    signal sinv[k];
    component sinv_range_checks[k];
    for (var idx = 0; idx < k; idx++) {
        sinv[idx] <-- sinv_comp[idx];
        sinv_range_checks[idx] = Num2Bits(n);
        sinv_range_checks[idx].in <== sinv[idx];
    }
    component sinv_check = BigMultModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        sinv_check.a[idx] <== sinv[idx];
        sinv_check.b[idx] <== s[idx];
        sinv_check.p[idx] <== order[idx];
    }
    for (var idx = 0; idx < k; idx++) {
        if (idx > 0) {
            sinv_check.out[idx] === 0;
        }
        if (idx == 0) {
            sinv_check.out[idx] === 1;
        }
    }

    // compute (h * sinv) mod n
    component g_coeff = BigMultModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        g_coeff.a[idx] <== sinv[idx];
        g_coeff.b[idx] <== msghash[idx];
        g_coeff.p[idx] <== order[idx];
    }

    // compute (h * sinv) * G
    component g_mult = ECDSAPrivToPub(n, k);
    for (var idx = 0; idx < k; idx++) {
        g_mult.privkey[idx] <== g_coeff.out[idx];
    }

    // compute (r * sinv) mod n
    component pubkey_coeff = BigMultModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        pubkey_coeff.a[idx] <== sinv[idx];
        pubkey_coeff.b[idx] <== r[idx];
        pubkey_coeff.p[idx] <== order[idx];
    }

    // compute (r * sinv) * pubkey
    component pubkey_mult = Secp256k1ScalarMult(n, k);
    for (var idx = 0; idx < k; idx++) {
        pubkey_mult.scalar[idx] <== pubkey_coeff.out[idx];
        pubkey_mult.point[0][idx] <== pubkey[0][idx];
        pubkey_mult.point[1][idx] <== pubkey[1][idx];
    }

    // compute (h * sinv) * G + (r * sinv) * pubkey
    component sum_res = Secp256k1AddUnequal(n, k);
    for (var idx = 0; idx < k; idx++) {
        sum_res.a[0][idx] <== g_mult.pubkey[0][idx];
        sum_res.a[1][idx] <== g_mult.pubkey[1][idx];
        sum_res.b[0][idx] <== pubkey_mult.out[0][idx];
        sum_res.b[1][idx] <== pubkey_mult.out[1][idx];
    }

    // compare sum_res.x with r
    component compare[k];
    signal num_equal[k - 1];
    for (var idx = 0; idx < k; idx++) {
        compare[idx] = IsEqual();
        compare[idx].in[0] <== r[idx];
        compare[idx].in[1] <== sum_res.out[0][idx];

        if (idx > 0) {
            if (idx == 1) {
                num_equal[idx - 1] <== compare[0].out + compare[1].out;
            } else {
                num_equal[idx - 1] <== num_equal[idx - 2] + compare[idx].out;
            }
        }
    }
    component res_comp = IsEqual();
    res_comp.in[0] <== k;
    res_comp.in[1] <== num_equal[k - 2];
    result <== res_comp.out;
}

template ERcover(n, k) {
    signal input r[k];
    signal input s[k];
    signal input v;
    signal input msghash[k];

    signal output pubKey[2][k];

    v * (v - 1) === 0; // v must be one or zero
    var p[100] = get_secp256k1_prime(n, k);
    var order[100] = get_secp256k1_order(n, k);

    // compute x ** 3
    component square = BigMultModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        square.a[idx] <== r[idx];
        square.b[idx] <== r[idx];
        square.p[idx] <== p[idx];
    }
    component triple = BigMultModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        triple.a[idx] <== square.out[idx];
        triple.b[idx] <== r[idx];
        triple.p[idx] <== p[idx];
    }
    // compute y ** 2 = x ** 3 + 7 (mod p)
    var tripleAddSeven = BigAdd(n, k);
    for (var idx = 0; idx < k; idx++) {
        tripleAddSeven.a[idx] <== triple.out[idx];
        if (idx == 0) {
            tripleAddSeven.b[idx] <== 7;
        } else {
            tripleAddSeven.b[idx] <== 0;
        }
        tripleAddSeven.p[idx] <== p[idx];
    }
    component ysquare = BigMod(n, k);
    for (var idx = 0; idx < k; idx++) {
        ysquare.a[idx] <== tripleAddSeven.out[idx];
        ysquare.p[idx] <== p[idx];
    }
    // compute sqrt(y ** 2)
    component ry = BigSqrtModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        ry.a[idx] <== ysquare.out[idx];
        ry.p[idx] <== p[idx];
    }
    component alternative_ry = BigSub(n, k);
    for (var idx = 0; idx < k; idx++) {
        alternative_ry.a[idx] <== p[idx];
        alternative_ry.b[idx] <== ry.out[idx];
    }
    // recover y from sqrt(y ** 2) and v
    component n2b = Num2Bits(n);
    n2b.in <== ry.out[0];
    component mux_ry = MultiMux1(k);
    // Are `v` and `ry` both odd?
    signal is_alternative = n2b.out[0] * v + n2b.out[0] + v;
    for (var i = 0; i < k; i++) {
        mux_ry.c[i][0] <== ry.out[i];
        mux_ry.c[i][1] <== alternative_ry.out[i];
    }

    // compute multiplicative inverse of r mod n
    var rinv_comp[100] = mod_inv(n, k, r, order);
    signal rinv[k];
    component rinv_range_checks[k];
    for (var idx = 0; idx < k; idx++) {
        rinv[idx] <-- rinv_comp[idx];
        rinv_range_checks[idx] = Num2Bits(n);
        rinv_range_checks[idx].in <== rinv[idx];
    }
    component sinv_check = BigMultModP(n, k);
    for (var idx = 0; idx < k; idx++) {
        rinv_check.a[idx] <== rinv[idx];
        rinv_check.b[idx] <== r[idx];
        rinv_check.p[idx] <== order[idx];
    }
    for (var idx = 0; idx < k; idx++) {
        if (idx > 0) {
            rinv_check.out[idx] === 0;
        }
        if (idx == 0) {
            rinv_check.out[idx] === 1;
        }
    }
}

// TODO: implement ECDSA extended verify
// r, s, and msghash have coordinates
// encoded with k registers of n bits each
// v is a single bit
// extended signature is (r, s, v)
template ECDSAExtendedVerify(n, k) {
    signal input r[k];
    signal input s[k];
    signal input v;
    signal input msghash[k];

    signal output result;
}
