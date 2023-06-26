// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/Sio2Adapter.sol";
import "../src/interfaces/ISio2LendingPool.sol";

contract DeploySio2Adapter is Script {
    Sio2Adapter implementationV1;
    TransparentUpgradeableProxy proxy;
    Sio2Adapter wrappedProxyV1;
    // MyContractV2 wrappedProxyV2;
    ProxyAdmin admin;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = new ProxyAdmin();

        implementationV1 = new Sio2Adapter();
        
        // deploy proxy contract and point it to implementation
        proxy = new TransparentUpgradeableProxy(address(implementationV1), address(admin), "");
        
        // wrap in ABI to support easier calls
        wrappedProxyV1 = Sio2Adapter(payable(address(proxy)));
        wrappedProxyV1.initialize(
            ISio2LendingPool(0x4df48B292C026f0340B60C582f58aa41E09fF0de),
            IERC20Upgradeable(0x6De33698e9e9b787e09d3Bd7771ef63557E148bb), //nASTR addr, but now its DAI for testing
            IERC20Upgradeable(0x7eC11c9aA33a2A306588a95e152C3Ec1855e2204), //snASTR, but now sDAI for testing
            ISio2IncentivesController(0xc41e6Da7F6E803514583f3b22b4Ff660CCD39B03),
            IERC20Upgradeable(0xcCA488aEEf7A1D5C633f877453784F025e7cF160), //reward token sio2
            Sio2AdapterAssetManager(0xa2D7550860E80DBB922258A1b34BA30bfe5c38A5),
            ISio2PriceOracle(0x5f7c3639A854a27DFf64B320De5C9CAF9C4Bd323)
        );

        // new implementation
        // MyContractV2 implementationV2 = new MyContractV2();
        // admin.upgrade(proxy, address(implementationV2));
        
        // wrappedProxyV2 = MyContractV2(address(proxy));
        // wrappedProxyV2.setY(200);

        // console.log(wrappedProxyV2.x(), wrappedProxyV2.y());

        vm.stopBroadcast();

        console.log("proxy address:", address(proxy));
        console.log("implementation address:", address(implementationV1));
    }

}

// pool 0x4df48B292C026f0340B60C582f58aa41E09fF0de
// == Logs ==
// proxy address: 0x5843F994dac00C761F483e535C95d90203e9830A
// implementation address: 0xFd48B48D83Ee50aB81A0D6d31E706410434A0006