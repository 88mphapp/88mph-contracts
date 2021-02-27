pragma solidity 0.5.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libs/DecMath.sol";

contract VaultWithDepositFeeMock is ERC20, ERC20Detailed {
    using SafeMath for uint256;
    using DecMath for uint256;

    uint256 PRECISION = 10**18;

    ERC20 public underlying;
    uint256 public depositFee;
    uint256 public feeCollected;

    constructor(address _underlying, uint256 _depositFee)
        public
        ERC20Detailed("yUSD", "yUSD", 18)
    {
        underlying = ERC20(_underlying);
        depositFee = _depositFee;
    }

    function deposit(uint256 tokenAmount) public {
        uint256 sharePrice = getPricePerFullShare();
        uint256 shareAmountAfterFee = tokenAmount.decdiv(sharePrice).decmul(PRECISION.sub(depositFee));
        uint256 tokenFee = tokenAmount.decmul(depositFee);
        _mint(msg.sender, shareAmountAfterFee);

        underlying.transferFrom(msg.sender, address(this), tokenAmount);

        feeCollected = feeCollected.add(tokenFee);
    }

    function withdraw(uint256 sharesAmount) public {
        uint256 sharePrice = getPricePerFullShare();
        uint256 underlyingAmount = sharesAmount.decmul(sharePrice);
        _burn(msg.sender, sharesAmount);

        underlying.transfer(msg.sender, underlyingAmount);
    }

    function getPricePerFullShare() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            return 10**18;
        }
        return underlying.balanceOf(address(this)).sub(feeCollected).decdiv(_totalSupply);
    }
}
