const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()

  const deployResult = await deploy('ZapCurve', {
    from: deployer
  })
  if (deployResult.newlyDeployed) {
    log(`ZapCurve deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['ZapCurve']
module.exports.dependencies = []
