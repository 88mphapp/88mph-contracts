const BigNumber = require('bignumber.js')

module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-network-config')

  const deployResult = await deploy('MPHMinter', {
    from: deployer,
    args: [
      config.mph,
      config.govTreasury,
      config.devWallet,
      BigNumber(config.devRewardMultiplier).toFixed()
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`MPHMinter deployed at ${deployResult.address}`)
    // Need to transfer MPHToken ownership to MPHMinter
  }
}
module.exports.tags = ['MPHMinter', 'MPHRewards']
module.exports.dependencies = []
