module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const poolConfig = require('../deploy-configs/get-pool-config')

  const deployResult = await deploy('DelegatedYVaultMarket', {
    from: deployer,
    args: [
      poolConfig.moneyMarketParams.vault,
      poolConfig.stablecoin
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`DelegatedYVaultMarket deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['DelegatedYVaultMarket']
module.exports.dependencies = []
