const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const poolConfig = require('../deploy-configs/get-pool-config')

  const deployResult = await deploy('LinearInterestModel', {
    from: deployer,
    args: [
      BigNumber(poolConfig.IRMultiplier).toFixed()
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`LinearInterestModel deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['LinearInterestModel']
module.exports.dependencies = []
