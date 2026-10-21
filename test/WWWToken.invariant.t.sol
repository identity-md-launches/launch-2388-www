// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WWWToken} from "../src/WWWToken.sol";

/// @dev A closed set of actors lets the invariant account for every token and allowance.
contract WWWTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    WWWToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = makeAddr("holder one");
        actors[1] = makeAddr("holder two");
        actors[2] = makeAddr("holder three");
        actors[3] = makeAddr("holder four");
        token = new WWWToken();
        assertTrue(token.transfer(actors[0], SUPPLY));
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(amountSeed, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Give revocation, small approvals and the infinite sentinel meaningful weight.
        // Also retain large finite approvals, which must not act as infinite.
        uint256 mode = amountSeed % 5;
        uint256 amount = mode == 0
            ? 0
            : mode == 1
                ? type(uint256).max
                : mode == 2 ? type(uint256).max - 1 : mode == 3 ? bound(amountSeed, 0, SUPPLY) : amountSeed;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < allowed ? expectedBalance[from] : allowed;
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function rejectOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 approvalSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approval = bound(approvalSeed, 0, SUPPLY - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[owner][spender] = approval;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, approval + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, approval + 1);
    }

    function rejectDelegatedOverBalance(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = balance + 1;
        uint256 approval = infinite ? type(uint256).max : amount;
        vm.prank(owner);
        assertTrue(token.approve(spender, approval));
        expectedAllowance[owner][spender] = approval;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
        // The invariant compares the unchanged model, including the allowance that
        // transferFrom tried to consume before discovering the insufficient balance.
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 available = expectedBalance[owner];
        uint256 allowed = expectedAllowance[owner][spender];
        if (delegated && allowed < available) available = allowed;
        uint256 amount = bound(amountSeed, 0, available);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        // At least one actor holds tokens. Select a funded holder so this action
        // cannot degenerate into a successful sequence of zero-value transfers.
        uint256 fromIndex = fromSeed % actors.length;
        for (uint256 i; i < actors.length && expectedBalance[actors[fromIndex]] == 0; ++i) {
            fromIndex = (fromIndex + 1) % actors.length;
        }
        address from = actors[fromIndex];
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = expectedBalance[from];
        assertGt(amount, 0, "no funded actor remains");
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] = 0;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract WWWTokenInvariantTest is Test {
    WWWTokenHandler private handler;
    WWWToken private token;

    function setUp() public {
        handler = new WWWTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = WWWTokenHandler.transfer.selector;
        selectors[1] = WWWTokenHandler.approve.selector;
        selectors[2] = WWWTokenHandler.transferFrom.selector;
        selectors[3] = WWWTokenHandler.rejectOverspend.selector;
        selectors[4] = WWWTokenHandler.revokeAndReject.selector;
        selectors[5] = WWWTokenHandler.rejectOverAllowance.selector;
        selectors[6] = WWWTokenHandler.rejectDelegatedOverBalance.selector;
        selectors[7] = WWWTokenHandler.rejectZeroRecipient.selector;
        selectors[8] = WWWTokenHandler.rejectZeroSpender.selector;
        selectors[9] = WWWTokenHandler.transferFullBalance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndEveryBalanceRemainAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_AllowancesMatchApprovedAndSpentAmounts() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(owner, address(handler)), 0);
        }
    }

    function invariant_MetadataRemainsFixed() public view {
        assertEq(token.name(), "www");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
    }

    /// @dev A deterministic witness that the handler reaches nonzero delegated
    /// spending, finite/infinite allowances and every intentional failure path.
    function test_HandlerExercisesApprovalLifecycleAndFailures() public {
        handler.transfer(0, 1, 100);
        handler.approve(1, 2, 103);
        handler.transferFrom(1, 3, 2, 60);
        assertEq(token.balanceOf(handler.actors(1)), 40);
        assertEq(token.balanceOf(handler.actors(3)), 60);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 43);
        invariant_SupplyAndEveryBalanceRemainAccountedFor();
        invariant_AllowancesMatchApprovedAndSpentAmounts();

        handler.rejectDelegatedOverBalance(1, 2, false);
        invariant_AllowancesMatchApprovedAndSpentAmounts();
        handler.revokeAndReject(1, 2, 3);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);
        handler.approve(3, 2, 1);
        handler.transferFrom(3, 0, 2, 60);
        assertEq(token.balanceOf(handler.actors(3)), 0);
        assertEq(token.allowance(handler.actors(3), handler.actors(2)), type(uint256).max);
        handler.rejectDelegatedOverBalance(1, 2, true);
        invariant_AllowancesMatchApprovedAndSpentAmounts();

        handler.rejectOverspend(1, 3);
        handler.rejectZeroRecipient(1, 2, 40, true);
        handler.rejectZeroRecipient(1, 2, 40, false);
        handler.rejectZeroSpender(1, type(uint256).max);
        handler.rejectOverAllowance(1, 2, 3);
        invariant_SupplyAndEveryBalanceRemainAccountedFor();
        invariant_AllowancesMatchApprovedAndSpentAmounts();

        handler.transferFullBalance(1, 0);
        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(2)), 40);
        invariant_SupplyAndEveryBalanceRemainAccountedFor();
        invariant_AllowancesMatchApprovedAndSpentAmounts();
        invariant_MetadataRemainsFixed();
    }
}
