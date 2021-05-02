// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "../tokens/NFT.sol";
import "../DInterest.sol";
import "../rewards/Vesting02.sol";

contract ZeroCouponBond is
    ERC20Upgradeable,
    ReentrancyGuardUpgradeable,
    IERC721ReceiverUpgradeable
{
    using SafeERC20Upgradeable for ERC20Upgradeable;

    DInterest public pool;
    ERC20Upgradeable public stablecoin;
    NFT public depositNFT;
    Vesting02 public vesting;
    uint256 public maturationTimestamp;
    uint256 public depositID;
    uint8 public _decimals;

    event WithdrawDeposit();
    event RedeemStablecoin(address indexed sender, uint256 amount);

    function initialize(
        address _creator,
        address _pool,
        address _vesting,
        uint256 _maturationTimestamp,
        uint256 _initialDepositAmount,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        __ReentrancyGuard_init();

        pool = DInterest(_pool);
        stablecoin = pool.stablecoin();
        depositNFT = pool.depositNFT();
        maturationTimestamp = _maturationTimestamp;
        vesting = Vesting02(_vesting);

        // set decimals to be the same as the underlying stablecoin
        _decimals = ERC20Upgradeable(address(pool.stablecoin())).decimals();

        // create deposit
        stablecoin.safeTransferFrom(
            _creator,
            address(this),
            _initialDepositAmount
        );
        stablecoin.safeApprove(address(pool), type(uint256).max);
        uint256 interestAmount;
        (depositID, interestAmount) = pool.deposit(
            _initialDepositAmount,
            maturationTimestamp
        );
        _mint(_creator, _initialDepositAmount + interestAmount);
        vesting.safeTransferFrom(
            address(this),
            _creator,
            vesting.depositIDToVestID(depositID)
        );
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(uint256 depositAmount) external nonReentrant {
        // transfer stablecoins from `msg.sender`
        stablecoin.safeTransferFrom(msg.sender, address(this), depositAmount);

        // topup deposit
        uint256 interestAmount = pool.topupDeposit(depositID, depositAmount);

        // mint zero coupon bonds to `msg.sender`
        _mint(msg.sender, depositAmount + interestAmount);
    }

    function earlyRedeem(uint256 bondAmount)
        external
        nonReentrant
        returns (uint256 stablecoinsRedeemed)
    {
        // burn bonds
        _burn(msg.sender, bondAmount);

        // withdraw funds from the pool
        stablecoinsRedeemed = pool.withdraw(depositID, bondAmount, true);

        // transfer funds to sender
        stablecoin.safeTransfer(msg.sender, stablecoinsRedeemed);
    }

    function withdrawDeposit() external nonReentrant {
        uint256 balance = pool.getDeposit(depositID).virtualTokenTotalSupply;
        require(balance > 0, "ZeroCouponBond: already withdrawn");
        pool.withdraw(depositID, balance, false);

        emit WithdrawDeposit();
    }

    function withdrawDepositNeeded() external view returns (bool) {
        return pool.getDeposit(depositID).virtualTokenTotalSupply > 0;
    }

    function redeem(uint256 amount, bool withdrawDepositIfNeeded)
        external
        nonReentrant
    {
        require(
            block.timestamp >= maturationTimestamp,
            "ZeroCouponBond: not mature"
        );

        if (withdrawDepositIfNeeded) {
            uint256 balance =
                pool.getDeposit(depositID).virtualTokenTotalSupply;
            if (balance > 0) {
                pool.withdraw(depositID, balance, false);
                emit WithdrawDeposit();
            }
        }

        // burn `amount` zero coupon bonds from `msg.sender`
        _burn(msg.sender, amount);

        // transfer `amount` stablecoins to `msg.sender`
        stablecoin.safeTransfer(msg.sender, amount);

        emit RedeemStablecoin(msg.sender, amount);
    }

    function onERC721Received(
        address, /*operator*/
        address, /*from*/
        uint256, /*tokenId*/
        bytes memory /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    uint256[43] private __gap;
}
