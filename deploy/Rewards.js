module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-config')

  const mphTokenDeployment = await get('MPHToken')

  const deployResult = await deploy('Rewards', {
    from: deployer,
    args: [
      mphTokenDeployment.address,
      config.rewardToken,
      config.oneSplitAddress,
      config.rewardStartTime
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`Rewards deployed at ${deployResult.address}`)

    const Rewards = artifacts.require('Rewards')
    const rewardsContract = await Rewards.at(deployResult.address)
    await rewardsContract.setRewardDistribution(config.rewardDistribution, { from: deployer })
  }
}
module.exports.tags = ['Rewards', 'MPHRewards']
module.exports.dependencies = ['MPHToken']
