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

        admin = ProxyAdmin(0xb8C8E0438ee2c1f81E67DaD7a3002f2D6Bc24772);
        proxy = TransparentUpgradeableProxy(payable(0xd940B0ead69063581BD0c679650d55b56fc9E043));

        // new implementation
        adapterNewImpl = new Sio2AdapterData();
        admin.upgrade(proxy, address(adapterNewImpl));

        console.log("New implementation:", address(adapterNewImpl));

        vm.stopBroadcast();
    }
}