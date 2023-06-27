// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract UpdateManager is Script {
    Sio2AdapterAssetManager managerNewImpl;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = ProxyAdmin(0xb8C8E0438ee2c1f81E67DaD7a3002f2D6Bc24772);
        proxy = TransparentUpgradeableProxy(payable(0x22925FE31c594aA8b1C079Ec54328cb6d87AF206));

        // new implementation
        managerNewImpl = new Sio2AdapterAssetManager();
        admin.upgrade(proxy, address(managerNewImpl));

        console.log("New manager implementation:", address(managerNewImpl));

        vm.stopBroadcast();
    }
}