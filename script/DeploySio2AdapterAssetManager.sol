// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2AdapterAssetManager.sol";
import "../src/interfaces/ISio2LendingPool.sol";

contract DeploySio2AdapterAssetManager is Script {
    Sio2AdapterAssetManager implementationV1;
    TransparentUpgradeableProxy proxy;
    Sio2AdapterAssetManager wrappedProxyV1;
    // MyContractV2 wrappedProxyV2;
    ProxyAdmin admin;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = new ProxyAdmin();

        implementationV1 = new Sio2AdapterAssetManager();
        
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(implementationV1), address(admin), "");
        
        // wrap in ABI to support easier calls
        wrappedProxyV1 = Sio2AdapterAssetManager(address(proxy));
        wrappedProxyV1.initialize(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de)
        );

        console.log("proxy address:", address(proxy));
        console.log("implementation address:", address(implementationV1));

        // new implementation
        // MyContractV2 implementationV2 = new MyContractV2();
        // admin.upgrade(proxy, address(implementationV2));
        
        // wrappedProxyV2 = MyContractV2(address(proxy));
        // wrappedProxyV2.setY(200);

        // console.log(wrappedProxyV2.x(), wrappedProxyV2.y());

        vm.stopBroadcast();
    }

}

// pool 0x4df48B292C026f0340B60C582f58aa41E09fF0de
// proxy address: 0xa2D7550860E80DBB922258A1b34BA30bfe5c38A5
// implementation address: 0xD173379add5d5E74Ba9233a6aa44F1F89393E26f