// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FundingMultitoken} from "./tokens/FundingMultitoken.sol";
import {NFT} from "./tokens/NFT.sol";
import {ZeroCouponBond} from "./zero-coupon-bond/ZeroCouponBond.sol";
import {EMAOracle} from "./models/interest-oracle/EMAOracle.sol";
import {AaveMarket} from "./moneymarkets/aave/AaveMarket.sol";
import {BProtocolMarket} from "./moneymarkets/bprotocol/BProtocolMarket.sol";
import {
    CompoundERC20Market
} from "./moneymarkets/compound/CompoundERC20Market.sol";
import {CreamERC20Market} from "./moneymarkets/cream/CreamERC20Market.sol";
import {HarvestMarket} from "./moneymarkets/harvest/HarvestMarket.sol";
import {YVaultMarket} from "./moneymarkets/yvault/YVaultMarket.sol";
import {DInterest} from "./DInterest.sol";
import {DInterestWithDepositFee} from "./DInterestWithDepositFee.sol";

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
        clone.initialize(_tokenName, _tokenSymbol);
        clone.transferOwnership(msg.sender);

        emit CreateClone("NFT", template, salt, address(clone));
        return clone;
    }

    function createFundingMultitoken(
        address template,
        bytes32 salt,
        string calldata _uri,
        address[] calldata _dividendTokens,
        address _wrapperTemplate,
        bool _deployWrapperOnMint,
        string memory _baseName,
        string memory _baseSymbol,
        uint8 _decimals
    ) external returns (FundingMultitoken) {
        FundingMultitoken clone =
            FundingMultitoken(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(
            msg.sender,
            _uri,
            _dividendTokens,
            _wrapperTemplate,
            _deployWrapperOnMint,
            _baseName,
            _baseSymbol,
            _decimals
        );

        emit CreateClone("FundingMultitoken", template, salt, address(clone));
        return clone;
    }

    function createZeroCouponBond(
        address template,
        bytes32 salt,
        address _pool,
        address _vesting,
        uint64 _maturationTimetstamp,
        uint256 _initialDepositAmount,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external returns (ZeroCouponBond) {
        ZeroCouponBond clone =
            ZeroCouponBond(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(
            msg.sender,
            _pool,
            _vesting,
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
        clone.initialize(
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
        address _aaveMining,
        address _rewards,
        address _rescuer,
        address _stablecoin
    ) external returns (AaveMarket) {
        AaveMarket clone = AaveMarket(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(
            _provider,
            _aToken,
            _aaveMining,
            _rewards,
            _rescuer,
            _stablecoin
        );
        clone.transferOwnership(msg.sender);

        emit CreateClone("AaveMarket", template, salt, address(clone));
        return clone;
    }

    function createBProtocolMarket(
        address template,
        bytes32 salt,
        address _bToken,
        address _bComptroller,
        address _rewards,
        address _rescuer,
        address _stablecoin
    ) external returns (BProtocolMarket) {
        BProtocolMarket clone =
            BProtocolMarket(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(
            _bToken,
            _bComptroller,
            _rewards,
            _rescuer,
            _stablecoin
        );
        clone.transferOwnership(msg.sender);

        emit CreateClone("BProtocolMarket", template, salt, address(clone));
        return clone;
    }

    function createCompoundERC20Market(
        address template,
        bytes32 salt,
        address _cToken,
        address _comptroller,
        address _rewards,
        address _rescuer,
        address _stablecoin
    ) external returns (CompoundERC20Market) {
        CompoundERC20Market clone =
            CompoundERC20Market(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(
            _cToken,
            _comptroller,
            _rewards,
            _rescuer,
            _stablecoin
        );
        clone.transferOwnership(msg.sender);

        emit CreateClone("CompoundERC20Market", template, salt, address(clone));
        return clone;
    }

    function createCreamERC20Market(
        address template,
        bytes32 salt,
        address _cToken,
        address _rescuer,
        address _stablecoin
    ) external returns (CreamERC20Market) {
        CreamERC20Market clone =
            CreamERC20Market(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(_cToken, _rescuer, _stablecoin);
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
        address _rescuer,
        address _stablecoin
    ) external returns (HarvestMarket) {
        HarvestMarket clone = HarvestMarket(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(_vault, _rewards, _stakingPool, _rescuer, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("HarvestMarket", template, salt, address(clone));
        return clone;
    }

    function createYVaultMarket(
        address template,
        bytes32 salt,
        address _vault,
        address _rescuer,
        address _stablecoin
    ) external returns (YVaultMarket) {
        YVaultMarket clone = YVaultMarket(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(_vault, _rescuer, _stablecoin);
        clone.transferOwnership(msg.sender);

        emit CreateClone("YVaultMarket", template, salt, address(clone));
        return clone;
    }

    function createDInterest(
        address template,
        bytes32 salt,
        uint64 _MaxDepositPeriod,
        uint256 _MinDepositAmount,
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
        clone.initialize(
            _MaxDepositPeriod,
            _MinDepositAmount,
            _stablecoin,
            _feeModel,
            _interestModel,
            _interestOracle,
            _depositNFT,
            _fundingMultitoken,
            _mphMinter
        );
        clone.transferOwnership(msg.sender, true, false);

        emit CreateClone("DInterest", template, salt, address(clone));
        return clone;
    }

    struct DInterestWithDepositFeeParams {
        uint64 _MaxDepositPeriod;
        uint256 _MinDepositAmount;
        uint256 _DepositFee;
        address _stablecoin;
        address _feeModel;
        address _interestModel;
        address _interestOracle;
        address _depositNFT;
        address _fundingMultitoken;
        address _mphMinter;
    }

    function createDInterestWithDepositFee(
        address template,
        bytes32 salt,
        DInterestWithDepositFeeParams calldata params
    ) external returns (DInterestWithDepositFee) {
        DInterestWithDepositFee clone =
            DInterestWithDepositFee(template.cloneDeterministic(salt));

        // initialize
        clone.initialize(
            params._MaxDepositPeriod,
            params._MinDepositAmount,
            params._DepositFee,
            params._stablecoin,
            params._feeModel,
            params._interestModel,
            params._interestOracle,
            params._depositNFT,
            params._fundingMultitoken,
            params._mphMinter
        );
        clone.transferOwnership(msg.sender, true, false);

        emit CreateClone(
            "DInterestWithDepositFee",
            template,
            salt,
            address(clone)
        );
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
