module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const config = require('../deploy-configs/get-network-config')

  const rewardsDeployment = await get('Rewards2')

  const deployResult = await deploy('Dumper2', {
    from: deployer,
    contract: 'Dumper',
    args: [
      config.oneSplitAddress,
      rewardsDeployment.address,
      config.rewardToken
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`Dumper deployed at ${deployResult.address}`)

    const Rewards = artifacts.require('Rewards')
    const rewardsContract = await Rewards.at(rewardsDeployment.address)
    await rewardsContract.setRewardDistribution(deployResult.address, true, { from: deployer })
  }
}
module.exports.tags = ['Dumper', 'MPHRewards']
module.exports.dependencies = ['Rewards']
