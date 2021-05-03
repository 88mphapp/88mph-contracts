// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {
    ERC721URIStorageUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NFT is ERC721URIStorageUpgradeable, OwnableUpgradeable {
    string internal _contractURI;
    string internal __baseURI;

    function initialize(string calldata tokenName, string calldata tokenSymbol)
        external
        initializer
    {
        __Ownable_init();
        __ERC721_init(tokenName, tokenSymbol);
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return __baseURI;
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function setContractURI(string calldata newURI) external onlyOwner {
        _contractURI = newURI;
    }

    function setTokenURI(uint256 tokenId, string calldata newURI) external {
        require(ownerOf(tokenId) == msg.sender, "NFT: not token owner");
        _setTokenURI(tokenId, newURI);
    }

    function setBaseURI(string calldata newURI) external onlyOwner {
        __baseURI = newURI;
    }

    uint256[48] private __gap;
}
