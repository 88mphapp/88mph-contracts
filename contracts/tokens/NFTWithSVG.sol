// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {
    ERC721URIStorageUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {NFT} from "./NFT.sol";
import {NFTDescriptor} from "../libs/NFTDescriptor.sol";

contract NFTWithSVG is NFT {
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        string memory _tokenURI = ERC721URIStorageUpgradeable.tokenURI(tokenId);
        return
            bytes(_tokenURI).length > 0
                ? _tokenURI
                : NFTDescriptor.constructTokenURI(
                    NFTDescriptor.URIParams({
                        tokenId: tokenId,
                        owner: ownerOf(tokenId),
                        name: name(),
                        symbol: symbol()
                    })
                );
    }
}
