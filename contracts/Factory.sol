// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libs/CloneFactory.sol";
import "./tokens/FundingMultitoken.sol";
import "./tokens/NFT.sol";
import "./zero-coupon-bond/ZeroCouponBond.sol";

contract Factory is CloneFactory {
    event CreateClone(string indexed contractName, address template, address _clone);

    function createNFT(
        address template,
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

        emit CreateClone("NFT", template, address(clone));
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

        emit CreateClone("FundingMultitoken", template, address(clone));
        return clone;
    }

    function createZeroCouponBond(
        address template,
        address _pool,
        uint256 _maturationTimetstamp,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (ZeroCouponBond) {
        ZeroCouponBond clone = ZeroCouponBond(createClone(template));

        // initialize
        clone.init(
            _pool,
            _maturationTimetstamp,
            _tokenName,
            _tokenSymbol
        );

        emit CreateClone("ZeroCouponBond", template, address(clone));
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
