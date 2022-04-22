module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const vesting02Deployment = await get("Vesting02");
  await deploy("ForwarderTemplate", {
    from: deployer,
    contract: "Forwarder",
    log: true,
    args: [vesting02Deployment.address],
  });
};
module.exports.tags = ["ForwarderTemplate"];
module.exports.dependencies = [];
