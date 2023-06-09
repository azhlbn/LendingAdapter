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

        admin = ProxyAdmin(0x558625fe3f28370BBCfff98350c09F555219622C);
        proxy = TransparentUpgradeableProxy(payable(0x4e7ED9Af1a838b1aD0d4D7047d2C0F96AB58D14e));

        // new implementation
        vestingNewImpl = new ALGMVesting();
        admin.upgrade(proxy, address(vestingNewImpl));

        console.log("New implementation:", address(vestingNewImpl));

        vm.stopBroadcast();
    }
}