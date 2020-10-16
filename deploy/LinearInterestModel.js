module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-config')

  const deployResult = await deploy('LinearInterestRateModel', {
    from: deployer,
    args: [
      config.IRMultiplier
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`LinearInterestRateModel deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['LinearInterestRateModel', 'DInterestPool']
module.exports.dependencies = []
