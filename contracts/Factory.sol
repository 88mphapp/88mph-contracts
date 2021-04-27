// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./tokens/FundingMultitoken.sol";
import "./tokens/NFT.sol";
import "./zero-coupon-bond/ZeroCouponBond.sol";
import "./models/interest-oracle/EMAOracle.sol";
import "./moneymarkets/aave/AaveMarket.sol";
import "./moneymarkets/compound/CompoundERC20Market.sol";
import "./moneymarkets/cream/CreamERC20Market.sol";
import "./moneymarkets/harvest/HarvestMarket.sol";
import "./moneymarkets/yvault/YVaultMarket.sol";
import "./DInterest.sol";

contract Factory {
    using Clones for address;

    event CreateClone(
        string indexed contractName,
        address template,
        bytes32 salt,
        address clone
    );

    function createNFT(
        address template,
        bytes32 salt,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (NFT) {
        NFT clone = NFT(template.cloneDeterministic(salt));

        // initialize
        clone.init(_tokenName, _tokenSymbol);
        clone.transferOwnership(msg.sender);

        emit CreateClone("NFT", template, salt, address(clone));
        return clone;
    }

    function createFundingMultitoken(
        address template,
        bytes32 salt,
        address target,
        string calldata _uri
    ) external returns (FundingMultitoken) {
        FundingMultitoken clone =
            FundingMultitoken(template.cloneDeterministic(salt));

        // initialize
        clone.init(target, msg.sender, _uri);

        emit CreateClone("FundingMultitoken", template, salt, address(clone));
        return clone;
    }

    function createZeroCouponBond(
        address template,
        bytes32 salt,
        address _pool,
        uint256 _maturationTimetstamp,
        uint256 _initialDepositAmount,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (ZeroCouponBond) {
        ZeroCouponBond clone =
            ZeroCouponBond(template.cloneDeterministic(salt));

        // initialize
        clone.init(
            msg.sender,
            _pool,
            _maturationTimetstamp,
            _initialDepositAmount,
            _tokenName,
            _tokenSymbol
        );

        emit CreateClone("ZeroCouponBond", template, salt, address(clone));
        return clone;
    }

    function createEMAOracle(
        address template,
        bytes32 salt,
        uint256 _emaInitial,
        uint256 _updateInterval,
        uint256 _smoothingFactor,
        uint256 _averageWindowInIntervals,
        address _moneyMarket
    ) external returns (EMAOracle) {
        EMAOracle clone = EMAOracle(template.cloneDeterministic(salt));

        // initialize
        clone.init(
            _emaInitial,
            _updateInterval,
            _smoothingFactor,
            _averageWindowInIntervals,
            _moneyMarket
        );

        emit CreateClone("EMAOracle", template, salt, address(clone));
        return clone;
    }

    function createAaveMarket(
        address template,
        bytes32 salt,
        address _provider,
        address _aToken,
        address _stablecoin
    ) external returns (AaveMarket) {
        AaveMarket clone = AaveMarket(template.cloneDeterministic(salt));

        // initialize
        clone.init(_provider, _aToken, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("AaveMarket", template, salt, address(clone));
        return clone;
    }

    function createCompoundERC20Market(
        address template,
        bytes32 salt,
        address _cToken,
        address _comptroller,
        address _rewards,
        address _stablecoin
    ) external returns (CompoundERC20Market) {
        CompoundERC20Market clone =
            CompoundERC20Market(template.cloneDeterministic(salt));

        // initialize
        clone.init(_cToken, _comptroller, _rewards, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("CompoundERC20Market", template, salt, address(clone));
        return clone;
    }

    function createCreamERC20Market(
        address template,
        bytes32 salt,
        address _cToken,
        address _stablecoin
    ) external returns (CreamERC20Market) {
        CreamERC20Market clone =
            CreamERC20Market(template.cloneDeterministic(salt));

        // initialize
        clone.init(_cToken, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("CreamERC20Market", template, salt, address(clone));
        return clone;
    }

    function createHarvestMarket(
        address template,
        bytes32 salt,
        address _vault,
        address _rewards,
        address _stakingPool,
        address _stablecoin
    ) external returns (HarvestMarket) {
        HarvestMarket clone = HarvestMarket(template.cloneDeterministic(salt));

        // initialize
        clone.init(_vault, _rewards, _stakingPool, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("HarvestMarket", template, salt, address(clone));
        return clone;
    }

    function createYVaultMarket(
        address template,
        bytes32 salt,
        address _vault,
        address _stablecoin
    ) external returns (YVaultMarket) {
        YVaultMarket clone = YVaultMarket(template.cloneDeterministic(salt));

        // initialize
        clone.init(_vault, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("YVaultMarket", template, salt, address(clone));
        return clone;
    }

    function createDInterest(
        address template,
        bytes32 salt,
        uint256 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
        address _moneyMarket,
        address _stablecoin,
        address _feeModel,
        address _interestModel,
        address _interestOracle,
        address _depositNFT,
        address _fundingMultitoken,
        address _mphMinter
    ) external returns (DInterest) {
        DInterest clone = DInterest(template.cloneDeterministic(salt));

        // initialize
        clone.init(
            _MaxDepositPeriod,
            _MinDepositAmount,
            _moneyMarket,
            _stablecoin,
            _feeModel,
            _interestModel,
            _interestOracle,
            _depositNFT,
            _fundingMultitoken,
            _mphMinter
        );
        clone.transferOwnership(msg.sender);

        emit CreateClone("DInterest", template, salt, address(clone));
        return clone;
    }

    function predictAddress(address template, bytes32 salt)
        external
        view
        returns (address)
    {
        return template.predictDeterministicAddress(salt);
    }
}
