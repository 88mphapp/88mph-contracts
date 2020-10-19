module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const poolConfig = require('../deploy-configs/pool.json')
  const aaveConfig = require('../deploy-configs/aave.json')

  const deployResult = await deploy('AaveMarket', {
    from: deployer,
    args: [
      aaveConfig.lendingPoolAddressesProvider,
      poolConfig.stablecoin
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`AaveMarket deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['AaveMarket']
module.exports.dependencies = []
