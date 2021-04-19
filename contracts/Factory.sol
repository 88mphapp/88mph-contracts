// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libs/CloneFactory.sol";
import "./tokens/FundingMultitoken.sol";
import "./tokens/NFT.sol";
import "./zero-coupon-bond/ZeroCouponBond.sol";
import "./models/interest-oracle/EMAOracle.sol";
import "./moneymarkets/aave/AaveMarket.sol";
import "./moneymarkets/compound/CompoundERC20Market.sol";
import "./moneymarkets/cream/CreamERC20Market.sol";
import "./moneymarkets/harvest/HarvestMarket.sol";
import "./moneymarkets/yvault/YVaultMarket.sol";

contract Factory is CloneFactory {
    event CreateClone(
        string indexed contractName,
        address template,
        address _clone
    );

    function createNFT(
        address template,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (NFT) {
        NFT clone = NFT(createClone(template));

        // initialize
        clone.init(_tokenName, _tokenSymbol);
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
        clone.init(_pool, _maturationTimetstamp, _tokenName, _tokenSymbol);

        emit CreateClone("ZeroCouponBond", template, address(clone));
        return clone;
    }

    function createEMAOracle(
        address template,
        uint256 _emaInitial,
        uint256 _updateInterval,
        uint256 _smoothingFactor,
        uint256 _averageWindowInIntervals,
        address _moneyMarket
    ) external returns (EMAOracle) {
        EMAOracle clone = EMAOracle(createClone(template));

        // initialize
        clone.init(
            _emaInitial,
            _updateInterval,
            _smoothingFactor,
            _averageWindowInIntervals,
            _moneyMarket
        );

        emit CreateClone("EMAOracle", template, address(clone));
        return clone;
    }

    function createAaveMarket(
        address template,
        address _provider,
        address _aToken,
        address _stablecoin
    ) external returns (AaveMarket) {
        AaveMarket clone = AaveMarket(createClone(template));

        // initialize
        clone.init(_provider, _aToken, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("AaveMarket", template, address(clone));
        return clone;
    }

    function createCompoundERC20Market(
        address template,
        address _cToken,
        address _comptroller,
        address _rewards,
        address _stablecoin
    ) external returns (CompoundERC20Market) {
        CompoundERC20Market clone = CompoundERC20Market(createClone(template));

        // initialize
        clone.init(_cToken, _comptroller, _rewards, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("CompoundERC20Market", template, address(clone));
        return clone;
    }

    function createCreamERC20Market(
        address template,
        address _cToken,
        address _stablecoin
    ) external returns (CreamERC20Market) {
        CreamERC20Market clone = CreamERC20Market(createClone(template));

        // initialize
        clone.init(_cToken, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("CreamERC20Market", template, address(clone));
        return clone;
    }

    function createHarvestMarket(
        address template,
        address _vault,
        address _rewards,
        address _stakingPool,
        address _stablecoin
    ) external returns (HarvestMarket) {
        HarvestMarket clone = HarvestMarket(createClone(template));

        // initialize
        clone.init(_vault, _rewards, _stakingPool, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("HarvestMarket", template, address(clone));
        return clone;
    }

    function createYVaultMarket(
        address template,
        address _vault,
        address _stablecoin
    ) external returns (YVaultMarket) {
        YVaultMarket clone = YVaultMarket(createClone(template));

        // initialize
        clone.init(_vault, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("YVaultMarket", template, address(clone));
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
