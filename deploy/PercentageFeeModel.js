module.exports = async ({ web3, getNamedAccounts, deployments, getChainId, artifacts }) => {
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()

  const dumperDeployment = await get('Dumper2')

  const deployResult = await deploy('PercentageFeeModel', {
    from: deployer,
    args: [
      dumperDeployment.address
    ]
  })
  if (deployResult.newlyDeployed) {
    log(`PercentageFeeModel deployed at ${deployResult.address}`)
  }
}
module.exports.tags = ['PercentageFeeModel']
module.exports.dependencies = ['Dumper']
