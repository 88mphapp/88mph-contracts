const hre = require("hardhat");
const fs = require("fs");

async function main() {
  // read in config
  const config = require("../deploy-configs/config.json");
  const poolConfig = require("../deploy-configs/get-pool-config");
  const poolName = poolConfig.name;
  const moneyMarketName = poolConfig.moneyMarket;

  // copy implementation deployment
  let templatePoolName = "";
  const toFileNames = [
    `${poolName} Deposit_Implementation.json`,
    `${poolName} Yield Token_Implementation.json`,
    `${poolName}_Implementation.json`,
    `${poolName}--${moneyMarketName}_Implementation.json`
  ];
  const protocol = config.protocol;
  switch (protocol) {
    case "aave":
      templatePoolName = "88mph DAI via Aave";
      break;
    case "compound":
      templatePoolName = "88mph DAI via Compound";
      break;
    case "harvest":
      templatePoolName = "88mph CRVRENWBTC via Harvest";
      break;
    default:
      throw new Error(`unknown protocol: ${protocol}`);
  }
  const fromFileNames = [
    `${templatePoolName} Deposit_Implementation.json`,
    `${templatePoolName} Yield Token_Implementation.json`,
    `${templatePoolName}_Implementation.json`,
    `${templatePoolName}--${moneyMarketName}_Implementation.json`
  ];
  const deploymentsRoot = "deployments/mainnet/";
  for (let i in fromFileNames) {
    const fromFileName = fromFileNames[i];
    const toFileName = toFileNames[i];
    fs.copyFileSync(
      deploymentsRoot + fromFileName,
      deploymentsRoot + toFileName
    );
  }

  // deploy
  await hre.run("deploy", {
    tags: "DInterest"
  });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
