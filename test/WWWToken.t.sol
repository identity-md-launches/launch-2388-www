// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WWWToken} from "../src/WWWToken.sol";

/// @dev Test-only deployer to exercise CREATE2 and subsequent factory transfers.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (WWWToken) {
        return new WWWToken{salt: salt}();
    }

    function move(WWWToken token, address to, uint256 amount) external {
        require(token.transfer(to, amount));
    }
}

contract WWWTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    WWWToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new WWWToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function test_MetadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "www");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMintEvent() public {
        vm.recordLogs();
        WWWToken fresh = new WWWToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_Create2FactoryReceivesSupplyAndDistributesExactAmounts() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        bytes32 salt = keccak256("www launch test");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(WWWToken).creationCode))
                    )
                )
            )
        );
        WWWToken launched = factory.deploy(salt);

        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.totalSupply(), SUPPLY);

        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool custody fixture");
        address remainder = makeAddr("remainder recipient");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 6 / 10;
        uint256 remainderShare = SUPPLY - swarmShare - poolShare;
        factory.move(launched, distributor, swarmShare);
        factory.move(launched, pool, poolShare);
        factory.move(launched, remainder, remainderShare);

        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarmShare);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.balanceOf(remainder), remainderShare);

        vm.prank(distributor);
        assertTrue(launched.transfer(alice, swarmShare));
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.balanceOf(alice), swarmShare);

        // Exercise token-side pool outflow and inflow, with no privileged exemption.
        vm.prank(pool);
        assertTrue(launched.transfer(bob, 10 ether));
        assertEq(launched.balanceOf(bob), 10 ether);
        vm.prank(bob);
        assertTrue(launched.transfer(pool, 10 ether));
        assertEq(launched.balanceOf(bob), 0);
        assertEq(launched.balanceOf(pool), poolShare);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 25 ether);
        assertTrue(token.transfer(alice, 25 ether));

        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireBalanceCanMoveAndMoveAgain() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferMoreThanBalanceRevertsWithoutChanges() public {
        assertTrue(token.transfer(alice, 5 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        vm.prank(alice);
        token.transfer(bob, 6 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 20 ether);
        assertTrue(token.approve(spender, 20 ether));
        assertTrue(token.approve(spender, 7 ether));
        assertEq(token.allowance(address(this), spender), 7 ether);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveDoesNotRequireCurrentBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(spender, 20 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 7 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 7 ether));
        assertEq(token.allowance(address(this), spender), 13 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 7 ether);
        assertEq(token.balanceOf(alice), 7 ether);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_TransferFromPreservesInfiniteAllowance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_TransferFromToSameOwnerSpendsAllowanceWithoutMovingBalance() public {
        assertTrue(token.approve(spender, 20 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 20 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromWithoutApprovalRevertsIncludingForDeployer() public {
        assertTrue(token.transfer(alice, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_AllowanceCannotBeUsedByAnotherSpender() public {
        assertTrue(token.approve(spender, 1 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_SpentAllowanceCannotBeReused() public {
        assertTrue(token.approve(spender, 5 ether));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_RevokingApprovalPreventsFurtherSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_FailedTransferFromRestoresAllowanceWhenBalanceIsInsufficient() public {
        assertTrue(token.transfer(alice, 5 ether));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6 ether);
        assertEq(token.allowance(alice, spender), 10 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_FailedTransferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(spender, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromZeroAddressCannotMint() public {
        vm.expectRevert();
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert();
        token.transferFrom(address(0), alice, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_NoMintBurnPauseSeizeOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(alice, 10 ether));
        bytes[] memory calls = new bytes[](14);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[7] = abi.encodeWithSignature("freeze(address)", alice);
        calls[8] = abi.encodeWithSignature("seize(address)", alice);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[10] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[11] = abi.encodeWithSignature("initialize(address)", bob);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer reached an unrequested privileged function");
            vm.prank(bob);
            (bool outsiderSucceeded,) = address(token).call(calls[i]);
            assertFalse(outsiderSucceeded, "outsider reached an unrequested privileged function");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 10 ether));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10 ether);
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool succeeded,) = address(token).call{value: 1 ether}("");
        assertFalse(succeeded);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        if (recipient == address(this)) {
            assertEq(token.balanceOf(address(this)), SUPPLY);
        } else {
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
            assertEq(token.balanceOf(recipient), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovedSpendingAccountsExactly(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approval);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientAllowanceRevertsAtomically(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY - 1);
        uint256 amount = bound(rawAmount, approval + 1, SUPPLY);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, amount);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testFuzz_InsufficientBalanceRevertsAtomically(uint256 rawBalance, uint256 rawAmount) public {
        uint256 balance = bound(rawBalance, 0, SUPPLY);
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        assertTrue(token.transfer(alice, balance));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(alice);
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
