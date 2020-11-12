module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-network-config')

  const mphTokenDeployment = await get('MPHToken')

  const deployResult = await deploy('Rewards2', {
    from: deployer,
    contract: 'Rewards',
    args: [
      mphTokenDeployment.address,
      config.rewardToken,
      config.rewardStartTime
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`Rewards2 deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['Rewards', 'MPHRewards']
module.exports.dependencies = ['MPHToken']
