// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.4;

import {SafeERC20} from "../../libs/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    AddressUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {MoneyMarket} from "../MoneyMarket.sol";
import {PRBMathUD60x18} from "prb-math/contracts/PRBMathUD60x18.sol";
import {IFERC20} from "./imports/IFERC20.sol";
import {IRewardsDistributor} from "./imports/IRewardsDistributor.sol";

contract FuseERC20Market is MoneyMarket {
    using PRBMathUD60x18 for uint256;
    using SafeERC20 for ERC20;
    using AddressUpgradeable for address;

    uint256 internal constant ERRCODE_OK = 0;

    IFERC20 public fToken;
    ERC20 public override stablecoin;
    address public rewards;
    IRewardsDistributor public rewardsDistributor;

    function initialize(
        address _fToken,
        address _rewardsDistributor,
        address _rescuer,
        address _stablecoin
    ) external initializer {
        __MoneyMarket_init(_rescuer);
        // Verify input addresses
        require(
            _fToken.isContract() && _stablecoin.isContract(),
            "FuseERC20Market: An input address is not a contract"
        );
        if (_rewardsDistributor != address(0)) {
            IRewardsDistributor rewDist =
                IRewardsDistributor(_rewardsDistributor);
            require(
                rewDist.isRewardsDistributor(),
                "RewardsDistributor: contract is not rewards distributor"
            );
            require(
                isMarketRewDist(_fToken, rewDist),
                "RewardsDistributor: rewards distributor not supported for this market"
            );
            rewardsDistributor = rewDist;
        }

        fToken = IFERC20(_fToken);
        stablecoin = ERC20(_stablecoin);
    }

    function isMarketRewDist(
        address _fToken,
        IRewardsDistributor _rewardsDistributor
    ) public view returns (bool) {
        unchecked {
            address[] memory markets = _rewardsDistributor.getAllMarkets();
            for (uint256 i = 0; i < markets.length; i++) {
                if (_fToken == markets[i]) return true;
            }
        }
        return false;
    }

    function deposit(uint256 amount) external override onlyOwner {
        require(amount > 0, "FuseERC20Market: amount is 0");

        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit `amount` stablecoin into cToken
        stablecoin.safeIncreaseAllowance(address(fToken), amount);
        require(
            fToken.mint(amount) == ERRCODE_OK,
            "FuseERC20Market: Failed to mint fToken"
        );
    }

    function withdraw(uint256 amountInUnderlying)
        external
        override
        onlyOwner
        returns (uint256 actualAmountWithdrawn)
    {
        require(
            amountInUnderlying > 0,
            "FuseERC20Market: amountInUnderlying is 0"
        );

        // Withdraw `amountInUnderlying` stablecoin from cToken
        require(
            fToken.redeemUnderlying(amountInUnderlying) == ERRCODE_OK,
            "FuseERC20Market: Failed to redeem"
        );

        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amountInUnderlying);

        return amountInUnderlying;
    }

    function claimRewards() external override {
        require(
            address(rewardsDistributor) != address(0),
            "RewardsDistributor: No Rewards"
        );
        address[] memory fTokens = new address[](1);
        fTokens[0] = address(fToken);

        ERC20 rewTok = ERC20(rewardsDistributor.rewardToken());
        uint256 beforeBalance = rewTok.balanceOf(address(this));

        rewardsDistributor.claimRewards(address(this), fTokens);

        rewTok.safeTransfer(
            rewards,
            rewTok.balanceOf(address(this)) - beforeBalance
        );
    }

    function setRewards(address newValue) external override onlyOwner {
        require(newValue != address(0), "FuseERC20Market: 0 address");
        rewards = newValue;
        emit ESetParamAddress(msg.sender, "rewards", newValue);
    }

    /**
        @dev IMPORTANT MUST READ
        This function is for restricting unauthorized accounts from taking funds
        and ensuring only tokens not used by the MoneyMarket can be rescued.
        IF YOU DON'T GET IT RIGHT YOU WILL LOSE PEOPLE'S MONEY
        MAKE SURE YOU DO ALL OF THE FOLLOWING
        1) You MUST override it in a MoneyMarket implementation.
        2) You MUST make `super._authorizeRescue(token, target);` the first line of your overriding function.
        3) You MUST revert during a call to this function if a token used by the MoneyMarket is being rescued.
        4) You SHOULD look at how existing MoneyMarkets do it as an example.
     */
    function _authorizeRescue(address token, address target)
        internal
        view
        override
    {
        super._authorizeRescue(token, target);
        require(token != address(fToken), "FuseERC20Market: no steal");
    }

    function _totalValue(uint256 currentIncomeIndex)
        internal
        view
        override
        returns (uint256)
    {
        uint256 fTokenBalance = fToken.balanceOf(address(this));
        return fTokenBalance.mul(currentIncomeIndex);
    }

    function _incomeIndex() internal override returns (uint256 index) {
        index = fToken.exchangeRateCurrent();
        require(index > 0, "FuseERC20Market: BAD_INDEX");
    }

    uint256[48] private __gap;
}
