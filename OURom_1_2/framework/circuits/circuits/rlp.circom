pragma circom 2.0.2;
include "../../node_modules/circomlib/circuits/switcher.circom";
include "../../node_modules/circomlib/circuits/bitify.circom";
include "../../node_modules/circomlib/circuits/comparators.circom";

/*
 * Get the sub-array of an array.
*/
template SubArray(maxDataLen, maxSubLen) {
    var indexBits = 0;
    while ((1 << indexBits) <= maxDataLen) {
        indexBits++;
    }

    signal input data[maxDataLen];
    signal input start;
    signal input end;
    signal output out[maxSubLen];
    signal output outLen;

    component lt1 = LessEqThan(indexBits);
    lt1.in[0] <== start;
    lt1.in[1] <== end;
    lt1.out === 1;

    component lt2 = LessEqThan(indexBits);
    lt2.in[0] <== end;
    lt2.in[1] <== maxDataLen;
    lt2.out === 1;

    component lt3 = LessEqThan(indexBits);
    lt3.in[0] <== end - start;
    lt3.in[1] <== maxSubLen;
    lt3.out === 1;

    outLen <== end - start;

    component indexes[maxSubLen];
    for (var i = 0; i < maxSubLen; i++) {
        indexes[i] <== Index(maxDataLen);
        for (var j = 0; j < maxDataLen; j++) {
            indexes[i].data[j] <== data[j];
            indexes[i].index <== start + j;
        }
    }

    for (var i = 0; i < maxSubLen; i++) {
        out[i] <== indexes[i].out;
    }
}

/*
 * Get the nth element of an array. When index is out of range, the output is 0.
*/
template Index(maxDataLen) {
    signal input data[maxDataLen];
    signal input index;
    signal output out;

    component select[maxDataLen];
    for (var i = 0; i < maxDataLen; i++) {
        select[i] = IsEqual();
        select[i].in[0] <== i;
        select[i].in[1] <== index;
    }

    signal sum[maxDataLen];
    sum[0] <== select[0].out * data[0];
    for (var i = 1; i < maxDataLen; i++) {
        sum[i] <== select[i].out * data[i] + sum[i-1];
    }
    out <== sum[maxDataLen-1];
}

/*
 * Check the validity of fixed-schema encoded list. Note that we only do a *shallow* check. The caller 
 * needs to do RLPCheckFixedList() for the inner list items if present.
 */
template RLPCheckFixedList(fieldLen, isListArray, fieldMaxLenArray, enforceInput) {
    assert(fieldLen == isListArray.length);
    assert(fieldLen == fieldMaxLenArray.length);
    var maxLen = 0;
    for (var i = 0; i < fieldLen; i++) {
        maxLen += fieldMaxLenArray[i];
    }

    // input bytes.
    signal input data[maxLen];
    // start position of data to check in the input bytes.
    signal input start;
    // is a valid RLP encoded list
    signal output valid;
    // offset of nth field in the data
    signal output offsetArray[fieldLen];
    // length of nth field in the data
    signal output lenArray[fieldLen];

    component byteCheck;
    if (enforceInput == 1) {
        // Do a num2bits enforce on each input
        for (var i = 0; i < maxLen; i++) {
            byteCheck = Num2Bits(8);
            byteCheck.in[i] <== data[i];
        }
    }

    component prefixChecks[fieldLen];
    for (var i = 0; i < fieldLen; i++) {
        prefixChecks[i] = RLPCheckPrefix(maxLen);
        for (var j = 0; j < fieldLen; j++) {
            prefixChecks[i].data[j] <== data[j];
        }
    }

}

template RLPCheckPrefix(maxLen) {
    signal input data[maxLen];
    signal input start;

    signal output valid;
    signal output end;
}

/*
 * Check the validity of a variable-size list that does not contain other lists.
 */
template RLPCheckSimpleList(maxFieldNum, fieldMaxLen, enforceInput) {
    // TODO
}

template RLPCheckListPrefix(maxLen) {
    signal input data[maxLen];
    signal input start;

    signal output valid;
    signal output prefixLen;
    signal output valueLen;

    var validVar = 0;
    var prefixLenVar = 0;
    var valueLenVar = 0;

    signal byte0, byte1, byte2, byte3;
    signal valid0, valid1, valid2, valid3;
    signal valueLen0, valueLen1, valueLen2, valueLen3;
    signal finalValueLen0, finalValueLen1, finalValueLen2, finalValueLen3;
    component index0, index1, index2, index3;
    component checkFirstByte1, checkFirstByte2, checkFirstByte3;
    component inRange1, inRange2, inRange3;

    index0 = Index(maxLen);
    // One prefix byte
    for (var i = 0; i < maxLen; i++) {
        index0.data[i] <== data[i];
    }
    index0.index <== start;
    byte0 <== index0.out;

    component lowerBound = LessThan(8);
    lowerBound.in[0] <== 191;
    lowerBound.in[1] <== byte0;
    component upperBound = LessThan(8);
    upperBound.in[0] <== byte0;
    upperBound.in[1] <== 248;
    valid0 <== lowerBound.out * upperBound.out;
    valueLen0 <== byte0 - 192;
    finalValueLen0 <== valid0 * valueLen0;

    // We can add the values because only one of them will be valid due to the property of
    // the RLP encoding. Any prefix with any value after it will only have one decoding theme.
    validVar += valid0;
    prefixLenVar += 1 * valid0;
    valueLenVar = valueLen0 * valid0;
    // One additional prefix byte
    if (maxLen > 55) {
        index1 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index1.data[i] <== data[i];
        }
        index1.index <== start + 1;
        byte1 <== index1.out;
        valueLen1 <== byte1;

        checkFirstByte1 = IsEqual();
        checkFirstByte1.in[0] <== 248;
        checkFirstByte1.in[1] <== byte0;
        inRange1 = LessThan(8);
        inRange1.in[0] <== 55;
        inRange1.in[1] <== valueLen1;
        valid1 <== checkFirstByte1.out * inRange1.out;

        validVar += valid1; 
        prefixLenVar += 2 * valid1;
        finalValueLen1 <== finalValueLen0 + valueLen1 * valid1;
        valueLenVar = finalValueLen1;
    }

    // Two additional prefix bytes
    if (maxLen >= 256 && maxLen < 65536) {
        index2 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index2.data[i] <== data[i];
        }
        index2.index <== start + 2;
        byte2 <== index2.out;
        // log("byte1: ", byte1);
        // log("byte2: ", byte2);
        valueLen2 <== byte2 + byte1 * (1 << 8);

        checkFirstByte2 = IsEqual();
        checkFirstByte2.in[0] <== 249;
        checkFirstByte2.in[1] <== byte0;
        inRange2 = LessThan(16);
        inRange2.in[0] <== 255;
        inRange2.in[1] <== valueLen2;
        valid2 <== checkFirstByte2.out * inRange2.out;

        validVar += valid2; 
        prefixLenVar += 3 * valid2;
        finalValueLen2 <== finalValueLen1 + valueLen2 * valid2;
        valueLenVar = finalValueLen2;
    }

    // Three additional prefix bytes
    if (maxLen >= 65536 && maxLen < 16777216) {
        index3 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index3.data[i] <== data[i];
        }
        index3.index <== start + 2;
        byte3 <== index3.out;
        valueLen3 <== byte3 + byte2 * (1 << 8) + byte1 * (1 << 16);

        checkFirstByte3 = IsEqual();
        checkFirstByte3.in[0] <== 250;
        checkFirstByte3.in[1] <== byte0;
        inRange3 = LessThan(24);
        inRange3.in[0] <== 65535;
        inRange3.in[1] <== valueLen3;
        valid3 <== checkFirstByte3.out * inRange3.out;

        validVar += valid3; 
        prefixLenVar += 4 * valid3;
        finalValueLen3 <== finalValueLen2+ valueLen3 * valid3;
        valueLenVar = finalValueLen3;
    }
    // We could add more here, but that's probably enough for now

    valid <== validVar;
    prefixLen <== prefixLenVar;
    valueLen <== valueLenVar;
}

/*
 * Checks the validity of an encoded string prefix.
 */
template RLPCheckStringPrefix(maxLen) {
    signal input data[maxLen];
    signal input start;

    signal output valid;
    signal output end;
    signal output len;

    // component lowerBound = LessThan(8);
    // lowerBound.in[0] <== 191;
    // lowerBound.in[1] <== byte;
    // component upperBound = LessThan(8);
    // upperBound.in[0] <== byte;
    // upperBound.in[1] <== 248;
}

template RLPCheckStringShortPrefix(maxLen) {

}

template RLPCheckStringLongPrefix(maxLen) {

}
