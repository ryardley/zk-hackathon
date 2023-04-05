import path from "path";

import { expect } from 'chai';
const circom_tester = require('circom_tester');
const wasm_tester = circom_tester.wasm;

import RLP from 'rlp';


describe("RLP decoding", function () {
    let circuit: any;
    before(async function () {
        console.log("Initialize the circuit test_rlp with wasm tester");
        circuit = await wasm_tester(path.join(__dirname, "circuits", "test_rlp.circom"));
        await circuit.loadConstraints();
        console.log("constraints: " + circuit.constraints.length);
    });

    var test_rlp_string = function (data) {
        console.log("Start test_rlp_decode");
        let encoded = RLP.encode(data);
        let RLP_CIRCUIT_MAX_INPUT_LEN = 10000;
        // encoded = smallRLP(header);
        // encoded header -> array of bigint
        let input = new Array(RLP_CIRCUIT_MAX_INPUT_LEN);
        for (let i = 0; i < encoded.length; i++) {
            input[i * 2] = BigInt(encoded[i] >> 4);
            input[i * 2 + 1] = BigInt(encoded[i] & 0xf);
        }
        for (let i = encoded.length * 2; i < RLP_CIRCUIT_MAX_INPUT_LEN; i++) {
            input[i] = 0n;
        }

    }

    const test_strings = [
        "", // emtpy string
        new Uint8Array([120]), // single byte
        "c", // single byte with one prefix byte
        "a".repeat(100), // 3 prefix bytes
        "a".repeat(10000), // 4 prefix bytes
    ];

    it('Testing bsc header, number ' + header.number, async function() {
        let witness = await circuit.calculateWitness(
            {
                "in": input
            });

        // account address == coinbase
        expect(witness[1]).to.equal(BigInt(header.coinbase));
        // chain ID
        expect(witness[2]).to.equal(BigInt(chainId));
        // block number
        expect(witness[3]).to.equal(BigInt(header.number));
        await circuit.checkConstraints(witness);
    });
    
    test_strings.forEach(test_rlp_string);
});