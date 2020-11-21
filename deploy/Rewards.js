module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-network-config')

  const deployResult = await deploy('Rewards', {
    from: deployer,
    contract: 'Rewards',
    args: [
      config.mph,
      config.rewardToken,
      config.rewardStartTime
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`Rewards deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['Rewards', 'MPHRewards']
module.exports.dependencies = []
