import path from "path";

import { expect, assert } from 'chai';
const circom_tester = require('circom_tester');
const wasm_tester = circom_tester.wasm;
import RLP from 'rlp';


describe("RLP decoding", function () {
    this.timeout(60 * 1000);

    let circuit: any;
    before(async function () {
        console.log("Initialize the circuit test_rlp with wasm tester");
        circuit = await wasm_tester(path.join(__dirname, "circuits", "test_list_prefix.circom"));
        await circuit.loadConstraints();
        console.log("constraints: " + circuit.constraints.length);
    });

    it("empty list", async () => {
        const encoded = RLP.encode([]);
        const input = new Array(10000);
        for (let i = 0; i < encoded.length; i ++) {
            input[i] = BigInt(encoded[i]);
        }
        for (let i = encoded.length; i < 10000; i++) {
            input[i] = BigInt(0);
        }
        const witness = await circuit.calculateWitness({ data: input });
        await circuit.checkConstraints(witness);
        await circuit.assertOut(witness, { valueLen: 0, prefixLen: 1 });
    });

    it("empty list", async () => {
        const target = [];
        for (let i = 0; i < 7777; i++) {
            target.push("x");
        }
        const encoded = RLP.encode(target);
        const input = new Array(10000);
        for (let i = 0; i < encoded.length; i ++) {
            input[i] = BigInt(encoded[i]);
        }
        for (let i = encoded.length; i < 10000; i++) {
            input[i] = BigInt(0);
        }
        const witness = await circuit.calculateWitness({ data: input });
        await circuit.checkConstraints(witness);
        await circuit.assertOut(witness, { valueLen: target.length, prefixLen: 3 });
    });
});