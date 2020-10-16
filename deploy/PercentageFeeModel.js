module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()

  const rewardsDeployment = await get('Rewards')

  const deployResult = await deploy('PercentageFeeModel', {
    from: deployer,
    args: [
      rewardsDeployment.address
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`PercentageFeeModel deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['PercentageFeeModel']
module.exports.dependencies = ['Rewards']
