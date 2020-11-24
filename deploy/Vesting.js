const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-network-config')

  const deployResult = await deploy('Vesting', {
    from: deployer,
    args: [
      config.mph
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`Vesting deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['Vesting']
module.exports.dependencies = []
