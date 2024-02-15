// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2Adapter.sol";
import "../src/Sio2AdapterAssetManager.sol";

contract Update is Script {
    Sio2Adapter adapterNewImpl;
    TransparentUpgradeableProxy proxyAdapter;

    Sio2AdapterAssetManager managerNewImpl;
    TransparentUpgradeableProxy proxyManager;

    ProxyAdmin admin;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = ProxyAdmin(0xb8C8E0438ee2c1f81E67DaD7a3002f2D6Bc24772);
        proxyAdapter = TransparentUpgradeableProxy(payable(0x7dE84319633850Bdabc557A1C61DA9E926cB4fF0));
        // proxyManager = TransparentUpgradeableProxy(payable(0x22925FE31c594aA8b1C079Ec54328cb6d87AF206));

        // new implementation
        adapterNewImpl = new Sio2Adapter();
        // managerNewImpl = new Sio2AdapterAssetManager();

        // admin.upgrade(proxyAdapter, address(adapterNewImpl));
        // admin.upgrade(proxyManager, address(managerNewImpl));

        // Sio2Adapter(payable(address(proxyAdapter))).updateParams();

        console.log("New adapter implementation:", address(adapterNewImpl));
        // console.log("New manager implementation:", address(managerNewImpl));

        vm.stopBroadcast();
    }
}

//   New adapter implementation: 0x934c114E9Ff8cF33Eae2b746837848e84d18137c
//   New manager implementation: 0x2cDDf30Fd329617BB871a9ab043A4c02E4fEd8a6