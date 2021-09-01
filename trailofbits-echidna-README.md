# 88mph < > Echidna

## Run the tests

To run the rests simply execute:

```
./trailofbits-run-echidna.sh
```

This requires Echidna from the 2.0 branch: https://github.com/crytic/echidna/pull/674.
Here you can find instructions on compiling from source which also work for version 2.0:
https://github.com/crytic/echidna#building-using-stack.

## Seeding Echidna from a recorded testing environment

As you can see in `trailofbits-echidna-config.yaml`
the Echidna tests are seeded from transactions which were previously recorded into
`trailofbits-transactions-recorded-by-etheno.json`.
This means that all Echidna tests run in the environment created by running those transactions in sequence.
The transactions were recorded when running a special test `test/Etheno.test.js`
which only includes the testing setup and runs no test transactions.
This allowed us to reuse the test setup created by 88mph and get results faster.

In order to know the addresses at which the test contracts were deployed
we modified the tests to print out a mapping of contract names and addresses to the console.

Keep in mind that if you do changes to the contracts deployed by the testing setup,
you need to record these transactions again.
Otherwise the changes will not be visible to the Echidna test.

## Generate `trailofbits-transactions-recorded-by-etheno.json`

### Setup

```
pip3.9 install etheno
npm install -g ganache-cli
solc-select install 0.8.3
solc-select use 0.8.3
```

### Deterministic addresses

By default Etheno undoes ganaches deterministic address generation by
prepending a set of randomly generated accounts which are different on every run.

To get deterministic addresses which don't require changing all addresses
used in the Echidna test whenever the setup transactions are recorded
open `Library/Frameworks/Python.framework/Versions/3.9/lib/python3.9/site-packages/etheno/__main__.py`
or the equivalent file on your system.

Then change the line containing

```
ganache_args = ganache_accounts + ['-g', str(args.gas_price), '-i', str(args.network_id)]
```

to

```
ganache_args = ['-g', str(args.gas_price), '-i', str(args.network_id)]
```

### Record transactions into `trailofbits-transactions-recorded-by-etheno.json`

#### In shell 1

```
etheno --ganache -x trailofbits-transactions-recorded-by-etheno.json --ganache-args "--mnemonic trailofbits --gasLimit 10000000"`
```

Etheno now appends json objects representing transactions to `trailofbits-transactions-recorded-by-etheno.json`.

#### In shell 2

```
npx hardhat --network localhost test test/Etheno.test.js
```

Wait for the test to complete.

### Back In in 1

Kill `etheno` with `ctrl-c`, `ctrl-c`.

`trailofbits-transactions-recorded-by-etheno.json` now contains the transactions made by `test/Etheno.test.js`.
