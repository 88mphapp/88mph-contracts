const fs = require("fs");
const { readdir, readFile } = require("fs/promises");

const excludedNetworks = ["rinkeby"];
const includedProtocols = [
  "Aave",
  "Benqi",
  "BProtocol",
  "Compound",
  "Geist",
  "Harvest",
];

/**
 * @dev Outputs a list of all money market addresses for each deployed network
 * Usage: in the project root directory, use `node scripts/output-reward-moneymarkets.js`
 * The result will be sent to stdout
 */

async function main() {
  // read list of networks
  let networkList = [];
  try {
    networkList = await readdir("./deployments/");
  } catch (err) {
    throw err;
  }
  networkList = networkList.filter((n) => !excludedNetworks.includes(n));

  // add moneymarkets for each network
  let result = {};
  for (const network of networkList) {
    let moneyMarketAddresses = [];
    let moneyMarketFileNameList;

    // get all moneymarket deployment file names
    try {
      moneyMarketFileNameList = await readdir(`./deployments/${network}`);
    } catch (err) {
      throw err;
    }
    moneyMarketFileNameList = moneyMarketFileNameList.filter((f) => {
      if (
        !(
          f.includes("88mph") &&
          f.includes("Market") &&
          !f.includes("Implementation") &&
          !f.includes("Proxy")
        )
      ) {
        // filter for money market contract
        return false;
      }
      // filter for included protocols
      for (const protocol of includedProtocols) {
        if (f.includes(`via ${protocol}--`)) {
          return true;
        }
      }
      return false;
    });

    // read all addresses of network
    for (const moneyMarketFileName of moneyMarketFileNameList) {
      // read in deployment object
      let deploymentObject;
      try {
        deploymentObject = JSON.parse(
          await readFile(`./deployments/${network}/${moneyMarketFileName}`)
        );
      } catch (err) {
        throw err;
      }

      // push address to network oracle list
      moneyMarketAddresses.push(deploymentObject.address);
    }

    // add network oracle address list to result
    result[network] = moneyMarketAddresses;
  }

  // send result to stdout
  console.log(JSON.stringify(result));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
