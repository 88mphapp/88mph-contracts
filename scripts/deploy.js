const env = require("@nomiclabs/buidler");

async function main() {
  await env.run("compile");

  const DInterest = env.artifacts.require("DInterest");
  const dInterestPool = await DInterest.new();
  console.log(`Deployed DInterest at address ${dInterestPool.address}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
