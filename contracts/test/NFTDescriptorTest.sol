// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../libs/NFTDescriptor.sol";
import "../libs/NFTSVG.sol";
import "../libs/HexStrings.sol";

contract NFTDescriptorTest {
    using HexStrings for uint256;

    function constructTokenURI(NFTDescriptor.URIParams calldata params)
        external
        pure
        returns (string memory)
    {
        return NFTDescriptor.constructTokenURI(params);
    }

    function addressToString(address _address)
        external
        pure
        returns (string memory)
    {
        return NFTDescriptor.addressToString(_address);
    }

    function generateSVGImage(NFTDescriptor.URIParams memory params)
        external
        pure
        returns (string memory)
    {
        return NFTDescriptor.generateSVGImage(params);
    }

    function toColorHex(address token, uint256 offset)
        external
        pure
        returns (string memory)
    {
        return NFTDescriptor.toColorHex(uint256(uint160(token)), offset);
    }

    function isRare(uint256 tokenId, string memory name)
        external
        pure
        returns (bool)
    {
        return NFTSVG.isRare(tokenId, name);
    }
}
