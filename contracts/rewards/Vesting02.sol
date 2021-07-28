// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.3;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "../libs/SafeERC20.sol";
import {
    ERC721URIStorageUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {BoringOwnable} from "../libs/BoringOwnable.sol";
import {
    MathUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {MPHMinter} from "./MPHMinter.sol";
import {DInterest} from "../DInterest.sol";
import {DecMath} from "../libs/DecMath.sol";

contract Vesting02 is ERC721URIStorageUpgradeable, BoringOwnable {
    using SafeERC20 for IERC20;
    using DecMath for uint256;

    uint256 internal constant PRECISION = 10**18;

    struct Vest {
        address pool;
        uint64 depositID;
        uint64 lastUpdateTimestamp;
        uint256 accumulatedAmount;
        uint256 withdrawnAmount;
        uint256 vestAmountPerStablecoinPerSecond;
    }
    Vest[] public vestList;
    mapping(address => mapping(uint64 => uint64)) public depositIDToVestID;

    MPHMinter public mphMinter;
    IERC20 public token;
    string internal _contractURI;
    string internal __baseURI;

    event ECreateVest(
        address indexed to,
        address indexed pool,
        uint64 depositID,
        uint64 vestID,
        uint256 vestAmountPerStablecoinPerSecond
    );
    event EUpdateVest(
        uint64 indexed vestID,
        address poolAddress,
        uint64 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount,
        uint256 vestAmountPerStablecoinPerSecond
    );
    event EWithdraw(
        address indexed sender,
        uint64 indexed vestID,
        uint256 withdrawnAmount
    );
    event ESetMPHMinter(address newValue);
    event EBoost(
        uint64 indexed vestID,
        uint256 vestAmountPerStablecoinPerSecond
    );

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
        uint64 depositID,
        uint256 vestAmountPerStablecoinPerSecond
    ) external returns (uint64 vestID) {
        require(
            address(msg.sender) == address(mphMinter),
            "Vesting02: not minter"
        );

        // create vest object
        require(block.timestamp <= type(uint64).max, "Vesting02: OVERFLOW");
        vestList.push(
            Vest({
                pool: pool,
                depositID: depositID,
                lastUpdateTimestamp: uint64(block.timestamp),
                accumulatedAmount: 0,
                withdrawnAmount: 0,
                vestAmountPerStablecoinPerSecond: vestAmountPerStablecoinPerSecond
            })
        );
        require(vestList.length <= type(uint64).max, "Vesting02: OVERFLOW");
        vestID = uint64(vestList.length); // 1-indexed
        depositIDToVestID[pool][depositID] = vestID;

        // mint NFT
        _safeMint(to, vestID);

        emit ECreateVest(
            to,
            pool,
            depositID,
            vestID,
            vestAmountPerStablecoinPerSecond
        );
    }

    function updateVestForDeposit(
        address poolAddress,
        uint64 depositID,
        uint256 currentDepositAmount,
        uint256 depositAmount,
        uint256 vestAmountPerStablecoinPerSecond
    ) external {
        require(
            address(msg.sender) == address(mphMinter),
            "Vesting02: not minter"
        );

        uint64 vestID = depositIDToVestID[poolAddress][depositID];
        Vest storage vestEntry = _getVest(vestID);
        DInterest pool = DInterest(poolAddress);
        DInterest.Deposit memory depositEntry =
            pool.getDeposit(vestEntry.depositID);
        uint256 currentTimestamp =
            MathUpgradeable.min(
                block.timestamp,
                depositEntry.maturationTimestamp
            );
        vestEntry.accumulatedAmount += (currentDepositAmount *
            (currentTimestamp - vestEntry.lastUpdateTimestamp))
            .decmul(vestEntry.vestAmountPerStablecoinPerSecond);
        require(block.timestamp <= type(uint64).max, "Vesting02: OVERFLOW");
        vestEntry.lastUpdateTimestamp = uint64(block.timestamp);
        vestEntry.vestAmountPerStablecoinPerSecond =
            (vestEntry.vestAmountPerStablecoinPerSecond *
                currentDepositAmount +
                vestAmountPerStablecoinPerSecond *
                depositAmount) /
            (currentDepositAmount + depositAmount);

        emit EUpdateVest(
            vestID,
            poolAddress,
            depositID,
            currentDepositAmount,
            depositAmount,
            vestAmountPerStablecoinPerSecond
        );
    }

    /**
        Public action functions
     */

    function withdraw(uint64 vestID)
        external
        returns (uint256 withdrawnAmount)
    {
        return _withdraw(vestID);
    }

    function multiWithdraw(uint64[] memory vestIDList) external {
        for (uint256 i = 0; i < vestIDList.length; i++) {
            _withdraw(vestIDList[i]);
        }
    }

    function _withdraw(uint64 vestID)
        internal
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

    function getVestWithdrawableAmount(uint64 vestID)
        external
        view
        returns (uint256)
    {
        return _getVestWithdrawableAmount(vestID);
    }

    function _getVestWithdrawableAmount(uint64 vestID)
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
        if (currentTimestamp < vestEntry.lastUpdateTimestamp) {
            return vestEntry.accumulatedAmount - vestEntry.withdrawnAmount;
        }
        uint256 depositAmount =
            depositEntry.virtualTokenTotalSupply.decdiv(
                PRECISION + depositEntry.interestRate
            );
        return
            vestEntry.accumulatedAmount +
            (depositAmount * (currentTimestamp - vestEntry.lastUpdateTimestamp))
                .decmul(vestEntry.vestAmountPerStablecoinPerSecond) -
            vestEntry.withdrawnAmount;
    }

    function getVest(uint64 vestID) external view returns (Vest memory) {
        return _getVest(vestID);
    }

    function _getVest(uint64 vestID) internal view returns (Vest storage) {
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

    /**
        Owner functions
     */

    function setBaseURI(string calldata newURI) external onlyOwner {
        __baseURI = newURI;
    }

    function boost(uint64 vestID, uint256 vestAmountPerStablecoinPerSecond)
        external
        onlyOwner
    {
        _getVest(vestID)
            .vestAmountPerStablecoinPerSecond = vestAmountPerStablecoinPerSecond;
        emit EBoost(vestID, vestAmountPerStablecoinPerSecond);
    }

    uint256[44] private __gap;
}
