// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/Strings.sol";
import "base64-sol/base64.sol";
import "./HexStrings.sol";
import "./NFTSVG.sol";

library NFTDescriptor {
    using Strings for uint256;
    using HexStrings for uint256;

    struct URIParams {
        uint256 tokenId;
        address owner;
        string name;
        string symbol;
    }

    function constructTokenURI(URIParams memory params)
        public
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                string(abi.encodePacked(params.name, "-NFT")),
                                '", "description":"',
                                generateDescription(),
                                '", "image": "',
                                "data:image/svg+xml;base64,",
                                Base64.encode(bytes(generateSVGImage(params))),
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function escapeQuotes(string memory symbol)
        internal
        pure
        returns (string memory)
    {
        bytes memory symbolBytes = bytes(symbol);
        uint8 quotesCount = 0;
        for (uint8 i = 0; i < symbolBytes.length; i++) {
            if (symbolBytes[i] == '"') {
                quotesCount++;
            }
        }
        if (quotesCount > 0) {
            bytes memory escapedBytes =
                new bytes(symbolBytes.length + (quotesCount));
            uint256 index;
            for (uint8 i = 0; i < symbolBytes.length; i++) {
                if (symbolBytes[i] == '"') {
                    escapedBytes[index++] = "\\";
                }
                escapedBytes[index++] = symbolBytes[i];
            }
            return string(escapedBytes);
        }
        return symbol;
    }

    function addressToString(address addr)
        internal
        pure
        returns (string memory)
    {
        return uint256(uint160(addr)).toHexString(20);
    }

    function toColorHex(uint256 base, uint256 offset)
        internal
        pure
        returns (string memory str)
    {
        return string((base >> offset).toHexStringNoPrefix(3));
    }

    function generateDescription() private pure returns (string memory) {
        return
            "This NFT represents a 88mph bond. The owner of this NFT can change URI.\\n";
    }

    function generateSVGImage(URIParams memory params)
        internal
        pure
        returns (string memory svg)
    {
        NFTSVG.SVGParams memory svgParams =
            NFTSVG.SVGParams({tokenId: params.tokenId, name: params.name});

        return NFTSVG.generateSVG(svgParams);
    }
}
