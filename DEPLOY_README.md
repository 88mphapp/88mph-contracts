# Deployment guide

## Set parameters

1. Put the name of the network you want to deploy to in `deployment-configs/network.json`
2. Ensure the network config file `deployment-configs/[networkName].json` has the correct global parameters
3. Ensure the pool config file `deployment-configs/pool.json` has the correct pool-scope parameters
4. Ensure the money market config file `deployment-configs/[moneyMarket].json` has the correct money market specific addresses

## Deploy DInterest pool

```bash
npx buidler deploy --tags DInterest --network [networkName]
```
