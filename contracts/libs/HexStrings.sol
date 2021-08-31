// SPDX-License-Identifier: MIT
// MODIFIED Uniswap-v3-periphery
pragma solidity 0.8.4;

library HexStrings {
    bytes16 internal constant ALPHABET = "0123456789abcdef";

    function toHexStringNoPrefix(uint256 value, uint256 length)
        internal
        pure
        returns (string memory)
    {
        bytes memory buffer = new bytes(2 * length);
        for (uint256 i = buffer.length; i > 0; i--) {
            buffer[i - 1] = ALPHABET[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
