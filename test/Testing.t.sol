// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Testing is Script {
    Sio2Adapter adapter = Sio2Adapter(payable(0x7dE84319633850Bdabc557A1C61DA9E926cB4fF0));
    ERC20 nastr = ERC20(0xE511ED88575C57767BAfb72BfD10775413E3F2b0);

    function test() public {
        address g = 0xbfE3B86005bfd5Ba1B1EFdbc614d9b2C16fBb1de;
        address third = 0xDB3e7cd8783d43553097f4B8529511E95D74cedD;

        vm.startPrank(g);

        console.log("Gs nastr balance here:", nastr.balanceOf(g));
        nastr.approve(address(adapter), 1e36);
        adapter.supply(100 ether);

        // nastr.transfer(g, 0.01 ether);

        vm.stopPrank();
    }
}

// g 0xbfE3B86005bfd5Ba1B1EFdbc614d9b2C16fBb1de