// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "../src/Sio2AdapterData.sol";
import "../src/interfaces/ISio2LendingPool.sol";

contract DeploySio2AdapterData is Script {
    Sio2Adapter adapter = Sio2Adapter(payable(0xAB06472A169e9eA3147A722464631D10553E384D));
    Sio2AdapterAssetManager assetManager = Sio2AdapterAssetManager(0x57c9f22168f315D33E1270b617F32F7940B89D67);
    ISio2LendingPool lendingPool = ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de);
    Sio2AdapterData implementationV1;
    TransparentUpgradeableProxy proxy;
    Sio2AdapterData wrappedProxyV1;
    ProxyAdmin admin;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = new ProxyAdmin();

        implementationV1 = new Sio2AdapterData();
        
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(implementationV1), address(admin), "");
        
        // wrap in ABI to support easier calls
        wrappedProxyV1 = Sio2AdapterData(payable(address(proxy)));
        wrappedProxyV1.initialize(
            adapter,
            assetManager,
            lendingPool
        );

        vm.stopBroadcast();

        console.log("proxy address:", address(proxy));
        console.log("implementation address:", address(implementationV1));
    }

}