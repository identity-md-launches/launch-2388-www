// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title www (WWW)
/// @notice Stop window shopping. See everything first.
/// @dev Fixed supply, 18 decimals, no administrative roles or post-deployment minting.
contract WWWToken is ERC20 {
    /// @notice One billion tokens expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When deployed through the launch factory, the factory receives all tokens.
    constructor() ERC20("www", "WWW") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
