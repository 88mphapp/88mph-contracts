module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()

  const deployResult = await deploy('MPHToken', {
    from: deployer
  })
  if (deployResult.newlyDeployed) {
    log(`MPHToken deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['MPHToken', 'MPHRewards']
module.exports.dependencies = []
