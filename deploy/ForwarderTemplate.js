module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("ForwarderTemplate", {
    from: deployer,
    contract: "Forwarder",
    log: true,
    args: ["0xA907C7c3D13248F08A3fb52BeB6D1C079507Eb4B"],
  });
};
module.exports.tags = ["ForwarderTemplate"];
module.exports.dependencies = [];
