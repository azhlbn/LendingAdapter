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

        admin = ProxyAdmin(0x4700c6795f8Acb98F397C13812D508780428C476);
        proxy = TransparentUpgradeableProxy(payable(0x57c9f22168f315D33E1270b617F32F7940B89D67));

        // new implementation
        managerNewImpl = new Sio2AdapterAssetManager();
        admin.upgrade(proxy, address(managerNewImpl));

        console.log("New manager implementation:", address(managerNewImpl));

        vm.stopBroadcast();
    }
}