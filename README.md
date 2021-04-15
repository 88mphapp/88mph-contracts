# 88mph-contracts-v3

Ethereum smart contracts for 88mph, a fixed-rate interest lending protocol.

Documentation may be found at [88mph.app/docs/smartcontract](https://88mph.app/docs/smartcontract/)

## Testing

After cloning the repo, in the project root directory, run the following to run the unit tests:

```
npm install
npx hardhat test
```

### Test coverage

After doing the above, run the following to generate test coverage information using `solidity-coverage`:

```
npx hardhat coverage
```

## Deploying

Read [DEPLOY_README.md](DEPLOY_README.md)