// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Sio2AdapterData.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract CustomTest is Test {
    Sio2Adapter adapter = Sio2Adapter(payable(0x7dE84319633850Bdabc557A1C61DA9E926cB4fF0));
    Sio2AdapterAssetManager manager = Sio2AdapterAssetManager(0x22925FE31c594aA8b1C079Ec54328cb6d87AF206);
    Sio2AdapterData data = Sio2AdapterData(0xd940B0ead69063581BD0c679650d55b56fc9E043);

    address igor = 0x4C6B3fcAe045fCA652528e20E7A28F8d88eA353d;

    function setUp() public {
    }

    function testTest() public {
        vm.startPrank(igor);

        adapter.repayFull{value: 22 ether}("ASTR");

        vm.stopPrank();
    }
}