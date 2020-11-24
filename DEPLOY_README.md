# Deployment guide

## Set parameters

1. Put the name of the network you want to deploy to and the pool you want to deploy in `deployment-configs/config.json`
2. Ensure the network config file `deployment-configs/networks/[networkName].json` has the correct global parameters
3. Ensure the pool config file `deployment-configs/pools/[poolName].json` has the correct pool-scope parameters
4. Ensure the protocol config file `deployment-configs/protocols/[moneyMarket].json` has the correct protocol specific addresses

## Deploy DInterest pool

```bash
npx buidler deploy --tags DInterest --network [networkName]
```

## Transfer shared contracts' ownerships to governance treasury

```bash
npx buidler deploy --tags transfer-ownerships --network [networkName]
```
