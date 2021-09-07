# 88mph-contracts

## Overview

88mph is a DeFi protocol for providing fixed-term fixed-rate interest. It does so by pooling deposits with differing maturations and fixed-rates together and putting the funds in a yield-generating protocol, such as Compound, Aave, and yEarn, to earn floating-rate interest. The debt incurred by the promised fixed-rate interest of a deposit is offered as yield tokens (or fundings as referred to in the contracts), which someone can purchase in exchange for the floating-rate interest generated by the corresponding deposit. Buyers of yield tokens thus speculate on the floating-rate yield generated by the underlying protocol, while decreasing the debt of the pool and the risk of insolvency.

### DInterest

The main contract is `DInterest`, which users interact with to deposit funds to earn fixed-rate interest, withdraw their funds, or purchase floating-rate bonds.

#### Deposit & withdraw

When a user makes a deposit, their funds are transferred to the `MoneyMarket` contract owned by the `DInterest` contract, which are then put to work in the underlying yield protocol. The user receives an ERC-721 NFT that represents the ownership of the deposit, which can be transferred.

Each deposit has a maturation date, after which the deposit NFT can be used to withdraw the deposited principal plus the promised fixed-rate interest. Before the maturation date, the user can also withdraw a deposit, though the fixed-rate interest would be forfeit, and an additional withdrawal fee would be applied. The user can choose to only withdraw a portion of a deposit.

The user may topup a deposit before its maturation, adding more principal to the deposit and earning more fixed-rate interest (albeit likely at a different fixed-rate). After a deposit is mature, the user can roll it over to create a new deposit using the principal + interest of the old deposit.

The NFT corresponding to a deposit is not burnt at any point, to preserve the potential artistic value of the metadata attached.

#### Buy yield tokens

When a user buys some yield tokens (YTs) of a particular deposit, the funds are transferred to `MoneyMarket` and deposited into the underlying yield protocol. The user will earn the future floating-rate interest generated by the portion of the deposit's principal whose debt is funded by the YT plus the funds used for purchasing the YT. For instance, if a 100 DAI deposit has 10 DAI of debt, then buying a YT using 5 DAI will allow you to earn interest on (5 / 10) \* 100 + 5 = 55 DAI.

The interest payout is triggered whenever a portion of the deposit is withdrawn, or when someone manually triggers a payout using `DInterest.payInterestToFunders()`.

### MoneyMarket

Money market is an abstract interface 88mphs uses to support different underlying yield protocols. Each protocol has its corresponding money market, for instance a `DInterest` pool using Aave to generate interest will use `AaveMarket` as its money market contract.

Money markets store all funds deposited into a `DInterest` pool.

### MPHMinter

The `MPHMinter` contract is in charge of the minting of MPH tokens. 88mph mints MPH tokens to reward users who make deposits or purchase floating-rate bonds. The governance treasury and the developer funds also receive MPH rewards any time new MPH is minted.

Whenever a user makes a deposit or purchases floating-rate bonds, `DInterest` makes a call to `MPHMinter` to mint MPH rewards. The reward could be vested using `Vesting` or `Vesting02`, or be distributed using `FundingMultitoken.distributeDividends()`.

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

**Notes**: the mainnet contract addresses are available here https://github.com/88mphapp/88mph-contracts/tree/v3/deployments/mainnet and the rinkeby here https://github.com/88mphapp/88mph-contracts/tree/v3/deployments/rinkeby
