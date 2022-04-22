module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const forwarderTemplateDeployment = await get("ForwarderTemplate");
  await deploy("Vesting03", {
    from: deployer,
    contract: "Vesting03",
    log: true,
    args: [forwarderTemplateDeployment.address],
  });
};
module.exports.tags = ["Vesting03"];
module.exports.dependencies = ["ForwarderTemplate"];
