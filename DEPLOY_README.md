# Deployment guide

## Set parameters

1. Put the name of the network you want to deploy to and the pool you want to deploy in `deployment-configs/config.json`
2. Ensure the network config file `deployment-configs/networks/[networkName].json` has the correct global parameters
3. Ensure the pool config file `deployment-configs/pools/[networkName]/[poolName].json` has the correct pool-scope parameters
4. Ensure the protocol config file `deployment-configs/protocols/[networkName]/[moneyMarketName].json` has the correct protocol specific addresses

## Deploy DInterest pool

```bash
npx buidler deploy --tags DInterest --network [networkName]
```

## Notes

### LinearDecayInterestModel

The interest amount as a function of the deposit length is a quadratic function that peaks at `t_mid = interestRateMultiplierIntercept / (2 * interestRateMultiplierSlope)`. In order to ensure the interest amount monotonically increases, we must have `t_max <= t_mid`, which means `interestRateMultiplierSlope <= interestRateMultiplierIntercept / (2 * t_max)`.
