// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract NFT is ERC721Upgradeable, OwnableUpgradeable {
    string internal _contractURI;

    function init(
        string calldata tokenName,
        string calldata tokenSymbol
    ) external initializer {
        __Ownable_init();
        __ERC721_init(tokenName, tokenSymbol);
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
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
}
