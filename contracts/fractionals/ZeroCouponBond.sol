pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "../DInterest.sol";
import "./FractionalDeposit.sol";
import "./FractionalDepositFactory.sol";

// OpenZeppelin contract modified to support cloned contracts
contract ClonedReentrancyGuard {
    bool internal _notEntered;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_notEntered, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _notEntered = false;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _notEntered = true;
    }
}

contract ZeroCouponBond is ERC20, ClonedReentrancyGuard {
    using SafeERC20 for ERC20;

    bool public initialized;
    DInterest public pool;
    FractionalDepositFactory public fractionalDepositFactory;
    ERC20 public stablecoin;
    uint256 public maturationTimestamp;
    string public name;
    string public symbol;
    uint8 public decimals;

    event Mint(
        address indexed sender,
        address indexed fractionalDepositAddress,
        uint256 amount
    );
    event RedeemFractionalDepositShares(
        address indexed sender,
        address indexed fractionalDepositAddress,
        uint256 fundingID
    );
    event RedeemStablecoin(address indexed sender, uint256 amount);

    function init(
        address _pool,
        address _fractionalDepositFactory,
        uint256 _maturationTimestamp,
        string calldata _tokenName,
        string calldata _tokenSymbol
    ) external {
        require(!initialized, "ZeroCouponBond: initialized");
        initialized = true;

        _notEntered = true;
        pool = DInterest(_pool);
        fractionalDepositFactory = FractionalDepositFactory(
            _fractionalDepositFactory
        );
        stablecoin = pool.stablecoin();
        maturationTimestamp = _maturationTimestamp;
        name = _tokenName;
        symbol = _tokenSymbol;

        // set decimals to be the same as the underlying stablecoin
        decimals = ERC20Detailed(address(pool.stablecoin())).decimals();
    }

    function mint(address fractionalDepositAddress, uint256 amount)
        external
        nonReentrant
    {
        FractionalDeposit fractionalDeposit =
            FractionalDeposit(fractionalDepositAddress);

        // verify the validity of the fractional deposit
        // 1. verify the contract is a clone of our trusted contract
        require(
            fractionalDepositFactory.isFractionalDeposit(
                fractionalDepositAddress
            ),
            "ZeroCouponBond: not fractional deposit"
        );
        // 2. verify the fractional deposit uses the same DInterest pool
        DInterest fdPool = fractionalDeposit.pool();
        require(
            address(fdPool) == address(pool),
            "ZeroCouponBond: pool mismatch"
        );
        // at this point we know the FD contract owns the deposit NFT
        // because the pool is non-zero, we know the init() function has been called
        // 3. verify the deposit is active
        require(fractionalDeposit.active(), "ZeroCouponBond: deposit inactive");
        // 4. verify the deposit's maturation time is on or before the maturation time
        // of this zero coupon bond
        uint256 fdMaturationTimestamp =
            pool.getDeposit(fractionalDeposit.nftID()).maturationTimestamp;
        require(
            fdMaturationTimestamp <= maturationTimestamp,
            "ZeroCouponBonds: maturation too late"
        );

        // transfer `amount` fractional deposit tokens from `msg.sender`
        fractionalDeposit.transferFrom(msg.sender, address(this), amount);

        // mint `amount` zero coupon bonds to `msg.sender`
        _mint(msg.sender, amount);

        emit Mint(msg.sender, fractionalDepositAddress, amount);
    }

    function redeemFractionalDepositShares(
        address fractionalDepositAddress,
        uint256 fundingID
    ) external nonReentrant {
        FractionalDeposit fractionalDeposit =
            FractionalDeposit(fractionalDepositAddress);

        uint256 balance = fractionalDeposit.balanceOf(address(this));
        fractionalDeposit.redeemShares(balance, fundingID);

        emit RedeemFractionalDepositShares(
            msg.sender,
            fractionalDepositAddress,
            fundingID
        );
    }

    function redeemStablecoin(uint256 amount)
        external
        nonReentrant
        returns (uint256 actualRedeemedAmount)
    {
        uint256 stablecoinBalance = stablecoin.balanceOf(address(this));
        actualRedeemedAmount = amount > stablecoinBalance
            ? stablecoinBalance
            : amount;

        // burn `actualRedeemedAmount` zero coupon bonds from `msg.sender`
        _burn(msg.sender, actualRedeemedAmount);

        // transfer `actualRedeemedAmount` stablecoins to `msg.sender`
        stablecoin.safeTransfer(msg.sender, actualRedeemedAmount);

        emit RedeemStablecoin(msg.sender, actualRedeemedAmount);
    }
}
