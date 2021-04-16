// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "../libs/CloneFactory.sol";
import "./DepositMultitoken.sol";
import "./FundingMultitoken.sol";

contract ERC1155Factory is CloneFactory {
    event CreateDepositMultitoken(address template, address _clone);
    event CreateFundingMultitoken(address template, address _clone);

    function createDepositMultitoken(address template, string calldata _uri)
        external
        returns (DepositMultitoken)
    {
        DepositMultitoken clone = DepositMultitoken(createClone(template));

        // initialize
        clone.init(msg.sender, _uri);

        emit CreateDepositMultitoken(template, address(clone));
        return clone;
    }

    function createFundingMultitoken(
        address template,
        address target,
        string calldata _uri
    ) external returns (FundingMultitoken) {
        FundingMultitoken clone = FundingMultitoken(createClone(template));

        // initialize
        clone.init(target, msg.sender, _uri);

        emit CreateFundingMultitoken(template, address(clone));
        return clone;
    }

    function isCloned(address template, address _query)
        external
        view
        returns (bool)
    {
        return isClone(template, _query);
    }
}
