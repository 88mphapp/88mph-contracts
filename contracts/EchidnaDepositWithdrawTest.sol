// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.4;

import "./mocks/ERC20Mock.sol";
import "./mocks/ATokenMock.sol";
import "./DInterest.sol";

// --------------------------------------------------------------------------------
// tests that `deposit` and `withdraw`:
// 1) revert if they should
// 2) don't revert if they shouldn't
// 3) return correct values
// 4) transfer correct amounts
// --------------------------------------------------------------------------------

contract EchidnaDepositWithdrawTest {
    // --------------------------------------------------------------------------------
    // event declarations
    // --------------------------------------------------------------------------------

    event Log(string message);
    event LogUint256(string message, uint256 x);

    // Echidna interprets emissions of this event as assertion failures
    event AssertionFailed(string message);

    // --------------------------------------------------------------------------------
    // contracts under test
    // --------------------------------------------------------------------------------

    DInterest private dinterest =
        DInterest(0x13d5Bf6416c98E81f667752Ee9591fAF8E98e029);
    ERC20Mock private mockToken =
        ERC20Mock(0xfFDF5B3243395e561f1b09aCAfB94cBD9e590a09);

    // --------------------------------------------------------------------------------
    // related to the generation of suitable maturation timestamps
    // --------------------------------------------------------------------------------

    // must be identical to `maxTimeDelay` in echidna config
    uint256 private MAX_POSITIVE_TIME_DELAY = 7500;
    // 25% chance of choosing a time in the past
    uint256 private MAX_NEGATIVE_TIME_DELAY = 2500;
    uint256 private TIME_DELAY_RANGE_LENGTH =
        MAX_NEGATIVE_TIME_DELAY + MAX_POSITIVE_TIME_DELAY;

    // returns a maturation timestamp equally distributed in the range
    // block.timestamp - MAX_NEGATIVE_TIME_DELAY to block.timestamp + MAX_POSITIVE_TIME_DELAY
    function randomMaturationTimestamp(uint256 seed)
        private
        view
        returns (uint64)
    {
        uint256 offset = seed % TIME_DELAY_RANGE_LENGTH;
        return uint64(block.timestamp - MAX_NEGATIVE_TIME_DELAY + offset);
    }

    // --------------------------------------------------------------------------------
    // related to minting interest
    // --------------------------------------------------------------------------------

    uint256 private lastMintingOfInterest = 0;
    ATokenMock private aTokenMock =
        ATokenMock(0x246956d319b8a075D59A801f73309fB26e7AB9a2);

    constructor() {
        lastMintingOfInterest = block.timestamp;
    }

    function mintInterest() private {
        aTokenMock.mintInterest(block.timestamp - lastMintingOfInterest);
        lastMintingOfInterest = block.timestamp;
    }

    // --------------------------------------------------------------------------------
    // remember state we need later.
    // exposed as optimization tests via `echidna_` prefix.
    // run with `--test-mode optimization` to verify
    // that the system is reaching expected states.
    // --------------------------------------------------------------------------------

    function echidna_mintedAmount() external view returns (uint256) {
        return mockToken.balanceOf(address(this));
    }

    function echidna_allowedAmount() external view returns (uint256) {
        return mockToken.allowance(address(this), address(dinterest));
    }

    uint256 public echidna_interestAmount = 0;
    uint64 public echidna_depositID = 0;

    uint256 public echidna_depositedAmount = 0;

    uint256 public echidna_matureWithdrawnAmount = 0;
    uint256 public echidna_immatureWithdrawnAmount = 0;

    uint256 public echidna_successfulWithdrawCount = 0;

    // --------------------------------------------------------------------------------
    // required, else `deposit` fails due to `this` not being able to receive the NFT
    // --------------------------------------------------------------------------------

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return EchidnaDepositWithdrawTest.onERC721Received.selector;
    }

    // --------------------------------------------------------------------------------
    // functions called by echidna
    // --------------------------------------------------------------------------------

    // mint some tokens so they can be approved
    function mint(uint256 seed) external {
        uint256 decimals = mockToken.decimals();
        assert(decimals == 6);
        uint256 exaScalingFactor = 18;
        // limit amount to 1 exa exa mockToken so tests are not cluttered with overflow errors
        // 18 * 3 = 54
        uint256 amount =
            seed % 10**(decimals + exaScalingFactor + exaScalingFactor);
        require(mockToken.balanceOf(address(this)) == 0);
        mockToken.mint(address(this), amount);
    }

    // approve some assets so they can be deposited
    function approveAll() external {
        require(
            mockToken.allowance(address(this), address(dinterest)) !=
                mockToken.balanceOf(address(this))
        );
        mockToken.approve(
            address(dinterest),
            mockToken.balanceOf(address(this))
        );
    }

    function deposit(uint256 amount, uint256 seed) external {
        // ensure we're all caught up
        mintInterest();

        // we get `BAD_INTEREST` if the amount is too low
        require(amount >= 10**mockToken.decimals());
        assert(10**mockToken.decimals() == 1000000);
        uint64 maturationTimestamp = randomMaturationTimestamp(seed);
        uint256 balanceBefore = mockToken.balanceOf(address(this));
        uint256 allowanceBefore =
            mockToken.allowance(address(this), address(dinterest));

        // --------------------------------------------------------------------------------
        // detect success or failure
        // --------------------------------------------------------------------------------

        bool success = true;
        emit LogUint256(
            "dinterest.MinDepositAmount()",
            dinterest.MinDepositAmount()
        );
        try dinterest.deposit(amount, maturationTimestamp) returns (
            uint64 depositID,
            uint256 interestAmount
        ) {
            emit Log("deposit success");
            uint256 balanceAfter = mockToken.balanceOf(address(this));
            uint256 transferredAmount = balanceBefore - balanceAfter;
            if (amount != transferredAmount) {
                emit AssertionFailed("deposit must transfer exactly `amount`");
            }
            if (depositID == 0) {
                emit AssertionFailed("deposit must return non-zero deposit ID");
            }
            if (interestAmount == 0) {
                emit AssertionFailed("deposit must return non-zero interest");
            }
            echidna_depositID = depositID;
            echidna_depositedAmount = amount;
            echidna_interestAmount = interestAmount;
            echidna_matureWithdrawnAmount = 0;
            echidna_immatureWithdrawnAmount = 0;
        } catch {
            success = false;
        }

        // --------------------------------------------------------------------------------
        // detect unexpected successes and stop on expected failures
        // --------------------------------------------------------------------------------

        if (amount > balanceBefore) {
            if (success) {
                emit AssertionFailed(
                    "deposit must revert if sender doesn't own at least `amount`"
                );
            } else {
                return;
            }
        }

        if (amount > allowanceBefore) {
            if (success) {
                emit AssertionFailed(
                    "deposit must revert if sender hasn't approved at least `amount`"
                );
                assert(false);
            } else {
                return;
            }
        }

        if (amount < dinterest.MinDepositAmount()) {
            if (success) {
                emit AssertionFailed(
                    "deposit must revert if `amount` is below the minimum"
                );
            } else {
                return;
            }
        }

        if (maturationTimestamp <= block.timestamp) {
            if (success) {
                emit AssertionFailed(
                    "deposit must revert if `maturationTimestamp` is not in the future"
                );
            } else {
                return;
            }
        }

        uint256 depositPeriod = maturationTimestamp - block.timestamp;
        if (depositPeriod > dinterest.MaxDepositPeriod()) {
            if (success) {
                emit AssertionFailed(
                    "deposit must revert if deposit period is above maximum"
                );
            } else {
                return;
            }
        }

        uint256 interest =
            dinterest.calculateInterestAmount(amount, depositPeriod);
        if (interest == 0) {
            if (success) {
                emit AssertionFailed("deposit must revert if interest is 0");
            } else {
                return;
            }
        }

        // --------------------------------------------------------------------------------
        // detect unexpected failures
        // --------------------------------------------------------------------------------

        if (!success) {
            emit AssertionFailed(
                "deposit must not revert if all preconditions are met"
            );
        }
    }

    function withdraw(uint256 amount, bool early) external {
        // ensure we're all caught up
        mintInterest();

        // --------------------------------------------------------------------------------
        // detect success or failure
        // --------------------------------------------------------------------------------

        uint256 balanceBefore = mockToken.balanceOf(address(this));
        uint256 depositAmountPlusInterest = 0;
        // the check is required because getDeposit fails with integer underflow otherwise
        if (dinterest.depositsLength() != 0) {
            depositAmountPlusInterest = dinterest
                .getDeposit(echidna_depositID)
                .virtualTokenTotalSupply;
        }
        emit LogUint256("depositAmountPlusInterest", depositAmountPlusInterest);

        bool success = true;
        try dinterest.withdraw(echidna_depositID, amount, early) returns (
            uint256 returnedAmount
        ) {
            emit Log("withdraw success");
            uint256 balanceAfter = mockToken.balanceOf(address(this));
            uint256 transferredAmount = balanceAfter - balanceBefore;
            if (returnedAmount != transferredAmount) {
                emit AssertionFailed(
                    "withdraw must return amount that it transferred"
                );
            }

            if (transferredAmount > depositAmountPlusInterest) {
                emit AssertionFailed(
                    "withdraw must not transfer more than the deposited amount plus interest"
                );
            }
            // TODO withdraw must transfer expected amount
            // uint256 expectedWithdrawnAmount =
            // TODO one should get exactly the promised interest

            if (early) {
                echidna_immatureWithdrawnAmount += returnedAmount;
            } else {
                echidna_matureWithdrawnAmount += returnedAmount;
            }
        } catch {
            success = false;
        }

        // --------------------------------------------------------------------------------
        // detect unexpected successes and stop on expected failures
        // --------------------------------------------------------------------------------

        if (echidna_depositID == 0) {
            if (success) {
                emit AssertionFailed(
                    "withdraw must revert if no deposit with `depositID` exists"
                );
            } else {
                return;
            }
        }

        if (amount == 0) {
            if (success) {
                emit AssertionFailed(
                    "withdraw must revert if `amount` is zero"
                );
            } else {
                return;
            }
        }

        uint64 maturationTimestamp =
            dinterest.getDeposit(echidna_depositID).maturationTimestamp;
        bool isActuallyEarly = block.timestamp < maturationTimestamp;
        if (early != isActuallyEarly) {
            if (success) {
                emit AssertionFailed(
                    "withdraw must revert if `early` doesn't match deposit state"
                );
            } else {
                return;
            }
        }

        // --------------------------------------------------------------------------------
        // detect unexpected failures
        // --------------------------------------------------------------------------------

        if (!success) {
            emit AssertionFailed(
                "withdraw must not revert if all preconditions are met"
            );
        }

        echidna_successfulWithdrawCount += 1;
    }
}
