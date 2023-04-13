# OUROs - Dedicated Task 1.2

As serialization is hard to do in pure circuits, it's best to designate the task to
witness calculation and use constraints to enforce correctness. Also, serialization/deserialization
of arbitrary structure is often useless in practical application, as the schema should be pre-defined
before constructing the circuit.

To simplify the circuit, we require the input to be padded with zero bytes, which is trivial to
implement outside the circuit and helps to reduce circuit size.

## Installation

### Install node

Node can be download at [this link](https://nodejs.org/en/download/).

### Install circom

Follow the [circom instruction](https://docs.circom.io/getting-started/installation/) to install circom command line.

## Quick Start

```
cd framework
npm install
npm run test
```