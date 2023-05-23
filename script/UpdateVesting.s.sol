// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/ALGMVesting.sol";

contract UpdateVesting is Script {
    ALGMVesting vestingNewImpl;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = ProxyAdmin(0x3E9c426d400754F967c8c807c136C50323193D60);
        proxy = TransparentUpgradeableProxy(payable(0x4F802625E02907b2CF0409a35288617e5CB7C762));

        // new implementation
        vestingNewImpl = new ALGMVesting();
        admin.upgrade(proxy, address(vestingNewImpl));

        console.log("New implementation:", address(vestingNewImpl));

        vm.stopBroadcast();
    }
}