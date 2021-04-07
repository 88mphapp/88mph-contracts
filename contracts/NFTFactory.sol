// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./libs/CloneFactory.sol";
import "./NFT.sol";

contract NFTFactory is CloneFactory {
    address public template;

    event CreateClone(address _clone);

    constructor(address _template) {
        template = _template;
    }

    function createClone(
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (NFT) {
        NFT clone = NFT(createClone(template));

        // initialize
        clone.init(
            _tokenName,
            _tokenSymbol
        );
        clone.transferOwnership(msg.sender);

        emit CreateClone(address(clone));
        return clone;
    }

    function isClone(address query) external view returns (bool) {
        return isClone(template, query);
    }
}
