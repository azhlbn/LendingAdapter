// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

contract CustomTest is Test {
    address user;
    address userOne = 0x0000000000000000000000000000000000000001;

    function setUp() public {
        user = vm.addr(1);
    }

    function testTest() public {
        vm.startPrank(userOne);

        console.log(userOne);

        vm.stopPrank();
    }

    event SomeEvent(address sender, uint256 value, string phrase);

    function testEventEmitting() public {
        Some some = new Some();

        vm.expectEmit(false, false, false, false);
        emit SomeEvent(msg.sender, 2, "hi");
        some.action();
    }
}

contract Some {
    event SomeEvent(address sender, uint256 value, string phrase);
    function action() public {
        emit SomeEvent(msg.sender, 1, "hi");
    }
}