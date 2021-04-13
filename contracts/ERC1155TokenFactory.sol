// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "./libs/CloneFactory.sol";
import "./ERC1155Token.sol";

contract ERC1155TokenFactory is CloneFactory {
    address public template;

    event CreateClone(address _clone);

    constructor(address _template) {
        template = _template;
    }

    function createClone(
        string calldata _uri
    ) external returns (ERC1155Token) {
        ERC1155Token clone = ERC1155Token(createClone(template));

        // initialize
        clone.init(
            msg.sender,
            _uri
        );

        emit CreateClone(address(clone));
        return clone;
    }

    function isClone(address _query) external view returns (bool) {
        return isClone(template, _query);
    }
}
