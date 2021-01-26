pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Detailed.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
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

contract ZeroCouponBond is ERC20, ClonedReentrancyGuard, IERC721Receiver {
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

        // infinite approval to fractional deposit factory to save gas during minting with NFT
        pool.depositNFT().setApprovalForAll(_fractionalDepositFactory, true);
        fractionalDepositFactory.mph().approve(
            _fractionalDepositFactory,
            uint256(-1)
        );
    }

    function mintWithDepositNFT(
        uint256 nftID,
        string calldata fractionalDepositName,
        string calldata fractionalDepositSymbol
    )
        external
        nonReentrant
        returns (
            uint256 zeroCouponBondsAmount,
            FractionalDeposit fractionalDeposit
        )
    {
        // ensure the deposit's maturation time is on or before that of the ZCB
        DInterest.Deposit memory depositStruct = pool.getDeposit(nftID);
        uint256 depositMaturationTimestamp = depositStruct.maturationTimestamp;
        require(
            depositMaturationTimestamp <= maturationTimestamp,
            "ZeroCouponBonds: maturation too late"
        );

        // transfer MPH from `msg.sender`
        MPHToken mph = fractionalDepositFactory.mph();
        mph.transferFrom(
            msg.sender,
            address(this),
            depositStruct.mintMPHAmount
        );

        // transfer deposit NFT from `msg.sender`
        NFT depositNFT = pool.depositNFT();
        depositNFT.safeTransferFrom(msg.sender, address(this), nftID);

        // call fractionalDepositFactory to create fractional deposit using NFT
        fractionalDeposit = fractionalDepositFactory.createFractionalDeposit(
            address(pool),
            nftID,
            fractionalDepositName,
            fractionalDepositSymbol
        );
        fractionalDeposit.transferOwnership(msg.sender);

        // mint zero coupon bonds to `msg.sender`
        zeroCouponBondsAmount = fractionalDeposit.totalSupply();
        _mint(msg.sender, zeroCouponBondsAmount);

        emit Mint(
            msg.sender,
            address(fractionalDeposit),
            zeroCouponBondsAmount
        );
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
        require(now >= maturationTimestamp, "ZeroCouponBond: not mature");

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

    /**
     * @notice Handle the receipt of an NFT
     * @dev The ERC721 smart contract calls this function on the recipient
     * after a {IERC721-safeTransferFrom}. This function MUST return the function selector,
     * otherwise the caller will revert the transaction. The selector to be
     * returned can be obtained as `this.onERC721Received.selector`. This
     * function MAY throw to revert and reject the transfer.
     * Note: the ERC721 contract address is always the message sender.
     * @param operator The address which called `safeTransferFrom` function
     * @param from The address which previously owned the token
     * @param tokenId The NFT identifier which is being transferred
     * @param data Additional data with no specified format
     * @return bytes4 `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
