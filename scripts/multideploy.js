const hre = require("hardhat");
const fs = require("fs");
const { accessSync, constants } = fs;
const requireNoCache = require("../deploy/requireNoCache");

async function main() {
  const configList = require("./multideploy-configs.json");

  let i = 0;
  for (let config of configList) {
    console.log(`Deploying pool: ${config.pool}`);

    // write config to deploy-configs/config.json
    fs.writeFileSync("deploy-configs/config.json", JSON.stringify(config));

    const poolConfig = requireNoCache("../deploy-configs/get-pool-config");
    const poolName = poolConfig.name;
    const moneyMarketName = poolConfig.moneyMarket;

    // copy implementation deployment
    let templatePoolName = "";
    const toFileNames = [
      `${poolName} Deposit_Implementation.json`,
      `${poolName} Yield Token_Implementation.json`,
      `${poolName}_Implementation.json`,
      `${poolName}--${moneyMarketName}_Implementation.json`,
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
      case "bprotocol":
        templatePoolName = "88mph DAI via BProtocol";
        break;
      case "cream":
        templatePoolName = "88mph FTT via Cream";
        break;
      case "benqi":
        templatePoolName = "88mph DAI via Benqi";
        break;
      case "scream":
        templatePoolName = "88mph DAI via Scream";
        break;
      case "geist":
        templatePoolName = "88mph DAI via Geist";
        break;
      default:
        throw new Error(`unknown protocol: ${protocol}`);
    }
    const fromFileNames = [
      `88mph DAI via Aave Deposit_Implementation.json`,
      `88mph DAI via Aave Yield Token_Implementation.json`,
      `88mph DAI via Aave_Implementation.json`,
      `${templatePoolName}--${moneyMarketName}_Implementation.json`,
    ];
    const deploymentsRoot = `deployments/${config.network}/`;
    for (let i in fromFileNames) {
      const fromFileName = fromFileNames[i];
      const toFileName = toFileNames[i];

      // if from file exists, copy, otherwise do nothing
      const fromPath = deploymentsRoot + fromFileName;
      try {
        accessSync(fromPath, constants.R_OK);
        fs.copyFileSync(fromPath, deploymentsRoot + toFileName);
      } catch {}
    }

    // deploy
    await hre.run("deploy", {
      tags: "DInterest",
    });

    // remove config from list in json file
    if (i == configList.length - 1) {
      fs.writeFileSync("scripts/multideploy-configs.json", "[]");
    } else {
      fs.writeFileSync(
        "scripts/multideploy-configs.json",
        JSON.stringify(configList.slice(i + 1))
      );
    }

    i++;
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
