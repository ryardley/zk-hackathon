pragma circom 2.0.2;
include "../../node_modules/circomlib/circuits/switcher.circom";
include "../../node_modules/circomlib/circuits/bitify.circom";
include "../../node_modules/circomlib/circuits/comparators.circom";
include "../../node_modules/circomlib/circuits/switcher.circom";

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

    component indexes[maxSubLen];
    for (var i = 0; i < maxSubLen; i++) {
        indexes[i] = Index(maxDataLen);
        for (var j = 0; j < maxDataLen; j++) {
            indexes[i].data[j] <== data[j];
        }
        indexes[i].index <== start + i;
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
template RLPCheckFixedList(maxLen, fieldNum, isListArray, enforceInput) {
    // input bytes.
    signal input data[maxLen];
    // start position of data to check in the input bytes.
    signal input start;
    // is a valid RLP encoded list
    signal output valid;
    // offset of nth field in the data
    signal output fieldStartArray[fieldNum];
    // length of nth field in the data
    signal output fieldEndArray[fieldNum];

    component byteCheck;
    if (enforceInput == 1) {
        // Do a num2bits enforce on each input
        for (var i = 0; i < maxLen; i++) {
            byteCheck = Num2Bits(8);
            byteCheck.in <== data[i];
        }
    }

    component listPrefixCheck = RLPCheckListPrefix(maxLen);
    for (var i = 0; i < maxLen; i++) {
        listPrefixCheck.data[i] <== data[i];
    }
    listPrefixCheck.start <== start;
    signal listEnd <== listPrefixCheck.prefixLen + listPrefixCheck.valueLen;

    var currentPosition = listPrefixCheck.prefixLen;
    component prefixChecks[fieldNum];
    for (var i = 0; i < fieldNum; i++) {
        prefixChecks[i] = RLPCheckPrefixSelect(maxLen, isListArray[i]);

        for (var j = 0; j < maxLen; j++) {
            prefixChecks[i].data[j] <== data[j];
        }
        prefixChecks[i].start <== currentPosition;
        fieldStartArray[i] <== currentPosition + prefixChecks[i].prefixLen;
        fieldEndArray[i] <== currentPosition + prefixChecks[i].prefixLen + prefixChecks[i].valueLen;
        // Do we need to check that all fieldStart and fieldEnd are valid and in range?
        // Theoretically someone could make a prefix that has size larger than or close to the
        // base field, but prefix to be outputed has a hard limit 16777216, so it should be fine.
        currentPosition += prefixChecks[i].prefixLen + prefixChecks[i].valueLen;
    }

    signal validProduct[fieldNum];
    validProduct[0] <== listPrefixCheck.valid * prefixChecks[0].valid;
    for (var i = 1; i < fieldNum; i++) {
        validProduct[i] <== validProduct[i-1] * prefixChecks[i].valid;
    }
    valid <== validProduct[fieldNum-1];
}

template RLPCheckPrefix(maxLen) {
    signal input data[maxLen];
    signal input start;

    signal output valid;
    signal output prefixLen;
    signal output valueLen;

    component checkListPrefix = RLPCheckListPrefix(maxLen);
    component checkStringPrefix = RLPCheckStringPrefix(maxLen);
    for (var i = 0; i < maxLen; i++) {
        checkListPrefix.data[i] <== data[i];
        checkStringPrefix.data[i] <== data[i];
    }
    checkListPrefix.start <== start;
    checkStringPrefix.start <== start;

    component prefixLenSwitcher = Switcher();
    prefixLenSwitcher.sel <== checkListPrefix.valid;
    prefixLenSwitcher.L <== checkStringPrefix.prefixLen;
    prefixLenSwitcher.R <== checkListPrefix.prefixLen;

    component valueLenSwitcher = Switcher();
    valueLenSwitcher.sel <== checkListPrefix.valid;
    valueLenSwitcher.L <== checkStringPrefix.valueLen;
    valueLenSwitcher.R <== checkListPrefix.valueLen;

    valid <== checkListPrefix.valid + checkStringPrefix.valid;
    prefixLen <== prefixLenSwitcher.outR;
    valueLen <== valueLenSwitcher.outR;
}

template RLPCheckPrefixSelect(maxLen, isList) {
    signal input data[maxLen];
    signal input start;

    signal output valid;
    signal output prefixLen;
    signal output valueLen;

    component checkListPrefix;
    component checkStringPrefix;
    var validVar, prefixLenVar, valueLenVar;

    if (isList) {
        checkListPrefix = RLPCheckListPrefix(maxLen);
        for (var i = 0; i < maxLen; i++) {
            checkListPrefix.data[i] <== data[i];
        }
        checkListPrefix.start <== start;
        validVar = checkListPrefix.valid;
        prefixLenVar = checkListPrefix.prefixLen;
        valueLenVar = checkListPrefix.valueLen;
    } else {
        checkStringPrefix = RLPCheckStringPrefix(maxLen);
        for (var i = 0; i < maxLen; i++) {
            checkStringPrefix.data[i] <== data[i];
        }
        checkStringPrefix.start <== start;
        validVar = checkStringPrefix.valid;
        prefixLenVar = checkStringPrefix.prefixLen;
        valueLenVar = checkStringPrefix.valueLen;
    }

    valid <== validVar;
    prefixLen <== prefixLenVar;
    valueLen <== valueLenVar;
}

/*
 * Check the validity of a variable-size list that does not contain other lists.
 */
template RLPCheckSimpleList(maxFieldNum, fieldMaxLen, enforceInput) {
    // TODO
}

template RLPCheckListPrefix(maxLen) {
    assert(maxLen < 16777216);
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
    if (maxLen >= 256) {
        index2 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index2.data[i] <== data[i];
        }
        index2.index <== start + 2;
        byte2 <== index2.out;
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
    if (maxLen >= 65536) {
        index3 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index3.data[i] <== data[i];
        }
        index3.index <== start + 3;
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
    assert(maxLen < 16777216);
    signal input data[maxLen];
    signal input start;

    signal output valid;
    signal output prefixLen;
    signal output valueLen;

    var validVar = 0;
    var prefixLenVar = 0;
    var valueLenVar = 0;

    signal byte0, byte1, byte2, byte3;
    signal validbyte, valid0, valid1, valid2, valid3;
    signal valueLenByte, valueLen0, valueLen1, valueLen2, valueLen3;
    signal finalValueByteLen, finalValueLen0, finalValueLen1, finalValueLen2, finalValueLen3;
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

    component singleByteUpperBound = LessThan(8);
    singleByteUpperBound.in[0] <== byte0;
    singleByteUpperBound.in[1] <== 128;
    validbyte <== singleByteUpperBound.out;
    valueLenByte <== 1;
    prefixLenVar += 0; // no prefix
    finalValueByteLen <== validbyte * valueLenByte;

    component lowerBound = LessThan(8);
    lowerBound.in[0] <== 127;
    lowerBound.in[1] <== byte0;
    component upperBound = LessThan(8);
    upperBound.in[0] <== byte0;
    upperBound.in[1] <== 184;
    valid0 <== lowerBound.out * upperBound.out;
    valueLen0 <== byte0 - 128;
    finalValueLen0 <== finalValueByteLen + valid0 * valueLen0;

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
        checkFirstByte1.in[0] <== 184;
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
    if (maxLen >= 256) {
        index2 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index2.data[i] <== data[i];
        }
        index2.index <== start + 2;
        byte2 <== index2.out;
        valueLen2 <== byte2 + byte1 * (1 << 8);

        checkFirstByte2 = IsEqual();
        checkFirstByte2.in[0] <== 185;
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
    if (maxLen >= 65536) {
        index3 = Index(maxLen);
        for (var i = 0; i < maxLen; i++) {
            index3.data[i] <== data[i];
        }
        index3.index <== start + 3;
        byte3 <== index3.out;
        valueLen3 <== byte3 + byte2 * (1 << 8) + byte1 * (1 << 16);

        checkFirstByte3 = IsEqual();
        checkFirstByte3.in[0] <== 186;
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
