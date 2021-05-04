# 88mph-contracts-v3

Ethereum smart contracts for 88mph, a fixed-rate interest lending protocol.

Documentation may be found at [88mph.app/docs/smartcontract](https://88mph.app/docs/smartcontract/)

## Local development

After cloning the repo, in the project root directory, run the following to set up the environment:

```bash
npm install
npm run prepare
```

### Run tests

```bash
npm test
```

### Generate documentation

```bash
npx hardhat docgen
```

The documentation is output to `/docgen`.

### Test coverage

After doing the above, run the following to generate test coverage information using `solidity-coverage`:

```bash
npx hardhat coverage
```

The coverage info is output to `coverage`.

### Run prettier

Use `prettier` to format all files.

```bash
npm run prettier
```

## Deployment

Read [DEPLOY_README.md](DEPLOY_README.md)
