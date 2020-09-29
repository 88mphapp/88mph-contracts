# 88mph-contracts

Ethereum smart contracts for 88mph, an upfront interest lending protocol.

Documentation may be found at [88mph.app/docs/smartcontract](https://88mph.app/docs/smartcontract/)

## Testing

After cloning the repo, in the project root directory, run the following to run the unit tests:

```
npm install
npx buidler test
```

### Test coverage

After doing the above, run the following to generate test coverage information using `solidity-coverage`:

```
npx buidler coverage
```

## Deploying

After cloning the repo, in the project root directory, run the following to deploy a version of 88mph to the Buidler test blockchain (the Aave-Dai pool is used in this example):

```
npm install
npx buidler compile
npx buidler run scripts/deploy-aave-dai.js --network buidlerevm
```
