pragma solidity 0.5.15;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "../IMoneyMarket.sol";
import "../../libs/DecMath.sol";
import "./imports/ICERC20.sol";

contract CompoundERC20Market is IMoneyMarket, Ownable {
    using DecMath for uint256;
    using SafeERC20 for ERC20Detailed;

    uint256 internal constant ERRCODE_OK = 0;

    ICERC20 public cToken;
    ERC20Detailed public stablecoin;

    constructor(address _cToken, address _stablecoin) public {
        cToken = ICERC20(_cToken);
        stablecoin = ERC20Detailed(_stablecoin);
    }

    function deposit(uint256 amount) external onlyOwner {
        // Transfer `amount` stablecoin from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Deposit `amount` stablecoin into cToken
        if (stablecoin.allowance(address(this), address(cToken)) > 0) {
            stablecoin.safeApprove(address(cToken), 0);
        }
        stablecoin.safeApprove(address(cToken), amount);
        require(
            cToken.mint(amount) == ERRCODE_OK,
            "CompoundERC20Market: Failed to mint cTokens"
        );
    }

    function withdraw(uint256 amountInUnderlying) external onlyOwner {
        // Withdraw `amountInUnderlying` stablecoin from cToken
        require(
            cToken.redeemUnderlying(amountInUnderlying) == ERRCODE_OK,
            "CompoundERC20Market: Failed to redeem"
        );

        // Transfer `amountInUnderlying` stablecoin to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amountInUnderlying);
    }

    function supplyRatePerSecond(uint256 blocktime)
        external
        view
        returns (uint256)
    {
        return cToken.supplyRatePerBlock().decdiv(blocktime);
    }

    function totalValue() external view returns (uint256) {
        uint256 cTokenBalance = cToken.balanceOf(address(this));
        // Amount of stablecoin units that 1 unit of cToken can be exchanged for, scaled by 10^18
        uint256 cTokenPrice = cToken.exchangeRateStored();
        return cTokenBalance.decmul(cTokenPrice);
    }

    function price() external view returns (uint256) {
        return cToken.exchangeRateStored();
    }
}
