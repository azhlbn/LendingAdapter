// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2AdapterData.sol";

contract UpdateAdapterData is Script {
    Sio2AdapterData adapterNewImpl;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = ProxyAdmin(0xE98BdF3c8ff2464A78693f2725845155f52da1f8);
        proxy = TransparentUpgradeableProxy(payable(0x01Daa46901103aED46F86d8be5376c3e12E8bd8b));

        // new implementation
        adapterNewImpl = new Sio2AdapterData();
        admin.upgrade(proxy, address(adapterNewImpl));

        console.log("New implementation:", address(adapterNewImpl));

        vm.stopBroadcast();
    }
}