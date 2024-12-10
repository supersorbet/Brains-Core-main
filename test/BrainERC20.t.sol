// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/forge-std/src/Test.sol";
import "../src/BrainERC20.sol";

contract BrainERC20Test is Test {
    BrainERC20 public token;

    function setUp() public {
        token = new BrainERC20();
        token.initialize("Brain Token", "BRAIN", 1000000 * 10**18, address(this));
    }

    function testInitialize() public {
        assertEq(token.name(), "Brain Token");
        assertEq(token.symbol(), "BRAIN");
        assertEq(token.totalSupply(), 1000000 * 10**18);
        assertEq(token.balanceOf(address(this)), 1000000 * 10**18);
    }

    function testMint() public {
        token.mint(address(1), 1000 * 10**18);
        assertEq(token.balanceOf(address(1)), 1000 * 10**18);
    }

    function testTransfer() public {
        token.transfer(address(1), 1000 * 10**18);
        assertEq(token.balanceOf(address(1)), 1000 * 10**18);
        assertEq(token.balanceOf(address(this)), 999000 * 10**18);
    }
}