// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/LiquidCrowdloan.sol";

contract UpdateCrowdloan is Script {
    LiquidCrowdloan crowdloanNewImpl;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = ProxyAdmin(0x558625fe3f28370BBCfff98350c09F555219622C);
        proxy = TransparentUpgradeableProxy(payable(0x5dc39BbD69d1B2173aB8eAB6e2C5774BFBF5fEa3));

        // new implementation
        crowdloanNewImpl = new LiquidCrowdloan();
        admin.upgrade(proxy, address(crowdloanNewImpl));

        console.log("New implementation:", address(crowdloanNewImpl));

        vm.stopBroadcast();
    }
}

// 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80