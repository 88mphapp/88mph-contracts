// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../libs/SafeERC20.sol";
import {
    ERC721URIStorageUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {MPHMinter} from "./MPHMinter.sol";
import {DInterest} from "../DInterest.sol";
import {DecMath} from "../libs/DecMath.sol";

contract Vesting02 is ERC721URIStorageUpgradeable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using DecMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    struct Vest {
        address pool;
        uint256 depositID;
        uint256 lastUpdateTimestamp;
        uint256 accumulatedAmount;
        uint256 withdrawnAmount;
        uint256 vestAmountPerStablecoinPerSecond;
    }
    Vest[] public vestList;
    mapping(uint256 => uint256) public depositIDToVestID;

    MPHMinter public mphMinter;
    IERC20 public token;
    string internal _contractURI;
    string internal __baseURI;

    event ECreateVest(
        address indexed to,
        address indexed pool,
        uint256 depositID,
        uint256 vestAmountPerStablecoinPerSecond
    );
    event EUpdateVest(uint256 indexed vestID);
    event EWithdraw(
        address indexed sender,
        uint256 indexed vestID,
        uint256 withdrawnAmount
    );
    event ESetMPHMinter(address newValue);

    function initialize(
        address _token,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external initializer {
        __Ownable_init();
        __ERC721_init(tokenName, tokenSymbol);

        token = IERC20(_token);
    }

    function setMPHMinter(address newValue) external onlyOwner {
        require(newValue != address(0), "Vesting02: 0 address");
        mphMinter = MPHMinter(newValue);
        emit ESetMPHMinter(newValue);
    }

    /**
        MPHMinter only functions
     */

    function createVestForDeposit(
        address to,
        address pool,
        uint256 depositID,
        uint256 vestAmountPerStablecoinPerSecond
    ) external returns (uint256 vestID) {
        require(
            address(msg.sender) == address(mphMinter),
            "Vesting02: not minter"
        );

        // create vest object
        vestList.push(
            Vest({
                pool: pool,
                depositID: depositID,
                lastUpdateTimestamp: block.timestamp,
                accumulatedAmount: 0,
                withdrawnAmount: 0,
                vestAmountPerStablecoinPerSecond: vestAmountPerStablecoinPerSecond
            })
        );
        vestID = vestList.length; // 1-indexed
        depositIDToVestID[depositID] = vestID;

        // mint NFT
        _safeMint(to, vestID);

        emit ECreateVest(to, pool, depositID, vestAmountPerStablecoinPerSecond);
    }

    function updateVestForDeposit(
        uint256 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount,
        uint256 vestAmountPerStablecoinPerSecond
    ) external {
        require(
            address(msg.sender) == address(mphMinter),
            "Vesting02: not minter"
        );

        uint256 vestID = depositIDToVestID[depositID];
        Vest storage vestEntry = _getVest(vestID);
        vestEntry.accumulatedAmount += _getVestWithdrawableAmount(vestID);
        vestEntry.lastUpdateTimestamp = block.timestamp;
        vestEntry.vestAmountPerStablecoinPerSecond =
            (vestEntry.vestAmountPerStablecoinPerSecond *
                currentDepositAmount +
                vestAmountPerStablecoinPerSecond *
                depositAmount) /
            (currentDepositAmount + depositAmount);

        emit EUpdateVest(vestID);
    }

    /**
        Public action functions
     */

    function withdraw(uint256 vestID)
        external
        returns (uint256 withdrawnAmount)
    {
        require(ownerOf(vestID) == msg.sender, "Vesting02: not owner");

        // compute withdrawable amount
        withdrawnAmount = _getVestWithdrawableAmount(vestID);
        if (withdrawnAmount == 0) {
            return 0;
        }

        // update vest object
        Vest storage vestEntry = _getVest(vestID);
        vestEntry.withdrawnAmount += withdrawnAmount;

        // mint tokens to vest recipient
        mphMinter.mintVested(msg.sender, withdrawnAmount);

        emit EWithdraw(msg.sender, vestID, withdrawnAmount);
    }

    /**
        Public getter functions
     */

    function getVestWithdrawableAmount(uint256 vestID)
        external
        view
        returns (uint256)
    {
        return _getVestWithdrawableAmount(vestID);
    }

    function _getVestWithdrawableAmount(uint256 vestID)
        internal
        view
        returns (uint256 withdrawableAmount)
    {
        // read vest data
        Vest memory vestEntry = _getVest(vestID);
        DInterest pool = DInterest(vestEntry.pool);
        DInterest.Deposit memory depositEntry =
            pool.getDeposit(vestEntry.depositID);

        // compute vested amount
        uint256 currentTimestamp =
            MathUpgradeable.min(
                block.timestamp,
                depositEntry.maturationTimestamp
            );
        uint256 depositAmount =
            depositEntry.virtualTokenTotalSupply.decdiv(
                PRECISION + depositEntry.interestRate
            );
        withdrawableAmount =
            vestEntry.accumulatedAmount +
            (depositAmount * (currentTimestamp - vestEntry.lastUpdateTimestamp))
                .decmul(vestEntry.vestAmountPerStablecoinPerSecond) -
            vestEntry.withdrawnAmount;
    }

    function getVest(uint256 vestID) external view returns (Vest memory) {
        return _getVest(vestID);
    }

    function _getVest(uint256 vestID) internal view returns (Vest storage) {
        return vestList[vestID - 1];
    }

    function numVests() external view returns (uint256) {
        return vestList.length;
    }

    /**
        NFT metadata
     */

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return __baseURI;
    }

    function setContractURI(string calldata newURI) external onlyOwner {
        _contractURI = newURI;
    }

    function setTokenURI(uint256 tokenId, string calldata newURI) external {
        require(ownerOf(tokenId) == msg.sender, "Vesting02: not token owner");
        _setTokenURI(tokenId, newURI);
    }

    function setBaseURI(string calldata newURI) external onlyOwner {
        __baseURI = newURI;
    }

    uint256[44] private __gap;
}
