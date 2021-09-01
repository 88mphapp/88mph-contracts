import { waffle, ethers } from "hardhat";
import { Fixture } from "ethereum-waffle";
import { expect, use } from "chai";
import { NFTDescriptor, NFTDescriptorTest, NFTWithSVG } from "../../typechain";

use(require("chai-bignumber")());

const overrides = { gasLimit: 9500000 };

describe("NFTWithSVG", async function() {
  const provider = waffle.provider;
  const wallets = provider.getWallets();
  const [wallet, owner] = wallets;
  const name = "88mph cDAI Pool Bond";
  const symbol = "88mph-cDAI-POOL-BOND";
  const tokenId = 10;

  let nft: NFTWithSVG;
  let nftDescriptor: NFTDescriptorTest;
  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;

  const nftDescriptorFixture: Fixture<{
    nft: NFTWithSVG;
    nftDescriptor: NFTDescriptorTest;
  }> = async () => {
    const NFTDescriptorLibraryFactory = await ethers.getContractFactory(
      "NFTDescriptor"
    );
    const nftDescriptorLibrary = (await NFTDescriptorLibraryFactory.deploy()) as NFTDescriptor;

    const [NFTWithSVG, NFTDescriptorTestFactory] = await Promise.all([
      ethers.getContractFactory("NFTWithSVG", {
        signer: owner,
        libraries: {
          NFTDescriptor: nftDescriptorLibrary.address
        }
      }),
      ethers.getContractFactory("NFTDescriptorTest", {
        libraries: {
          NFTDescriptor: nftDescriptorLibrary.address
        }
      })
    ]);
    const nft = (await NFTWithSVG.deploy(overrides)) as NFTWithSVG;
    const nftDescriptor = (await NFTDescriptorTestFactory.deploy(
      overrides
    )) as NFTDescriptorTest;

    return { nft, nftDescriptor };
  };

  before("create fixture loader", async () => {
    loadFixture = waffle.createFixtureLoader(wallets);
  });

  beforeEach("load fixture", async function() {
    ({ nft, nftDescriptor } = await loadFixture(nftDescriptorFixture));
    await nft.connect(owner).initialize(name, symbol);
    await nft.connect(owner)["mint(address,uint256)"](wallet.address, tokenId);
  });

  function extractJSONFromURI(
    uri: string
  ): { name: string; description: string; image: string } {
    const encodedJSON = uri.substr("data:application/json;base64,".length);
    const decodedJSON = Buffer.from(encodedJSON, "base64").toString("utf8");
    return JSON.parse(decodedJSON);
  }
  it("NFTDescriptorTest: constructURIParams", async function() {
    const params = {
      tokenId: tokenId,
      owner: wallet.address,
      name: await nft.name(),
      symbol: await nft.symbol()
    };
    const expectedTokenUri = {
      name: `${name}-NFT`,
      description:
        "This NFT represents a 88mph bond. The owner of this NFT can change URI.\n"
    };
    const json = extractJSONFromURI(
      await nftDescriptor.constructTokenURI(params)
    );
    console.log("json.image :>> ", json.image);

    const base64Str = json.image.replace("data:image/svg+xml;base64,", "");

    expect(json.description).to.equal(expectedTokenUri.description);
    expect(json.name).to.equal(expectedTokenUri.name);
  });
  it("get name, symbol, contractURI", async function() {
    expect(await nft.name()).to.equal(name);
    expect(await nft.symbol()).to.equal(symbol);
    expect(await nft.contractURI()).to.equal("");
  });
  it("setTokenURI: get correct tokenURI", async function() {
    const params = {
      tokenId: tokenId,
      owner: wallet.address,
      name: await nft.name(),
      symbol: await nft.symbol()
    };
    expect(await nft.tokenURI(params.tokenId)).to.eq(
      await nftDescriptor.constructTokenURI(params)
    );
  });
  it("setTokenURI: NFT owner set a new tokenURI", async function() {
    const newUri = "https://www.google.com/hoge";
    await nft.connect(wallet).setTokenURI(tokenId, newUri);
    expect(await nft.tokenURI(tokenId)).to.equal(newUri);
  });
});
