// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../src/LiquidCrowdloan.sol";
import "../src/ALGMVesting.sol";
import "../test/mocs/MockERC20.sol";
import "../src/DappsStakingMock.sol";

contract DeployCrowdloanVesting is Script {
    LiquidCrowdloan crowdloanImpl;
    TransparentUpgradeableProxy crowdloanProxy;
    ALGMVesting vestingImpl;
    TransparentUpgradeableProxy vestingProxy;
    ALGMVesting vestingWrappedProxy;
    LiquidCrowdloan crowdloanWrappedProxy;

    DappsStakingMock dappsStaking;

    MockERC20 algm;
    MockERC20 aastr;

    ProxyAdmin admin;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        admin = new ProxyAdmin();

        crowdloanImpl = new LiquidCrowdloan();
        vestingImpl = new ALGMVesting();

        // algm = new MockERC20("Algem", "ALGM");
        // aastr = new MockERC20("aASTR", "aASTR");

        dappsStaking = new DappsStakingMock();
        
        // deploy proxy contract and point it to implementation
        vestingProxy = new TransparentUpgradeableProxy(address(vestingImpl), address(admin), "");
        crowdloanProxy = new TransparentUpgradeableProxy(address(crowdloanImpl), address(admin), "");
        
        vestingWrappedProxy = ALGMVesting(address(vestingProxy));
        vestingWrappedProxy.initialize(
            IERC20Upgradeable(0xFFfFFFFF00000000000000000000000000000530)
        );

        crowdloanWrappedProxy = LiquidCrowdloan(payable(address(crowdloanProxy)));
        crowdloanWrappedProxy.initialize(
            vestingWrappedProxy,
            address(1),
            0xffFffffF0000000000000000000000000000052E,
            0xFFfFFFFF00000000000000000000000000000530,
            address(dappsStaking)
        );

        vestingWrappedProxy.addManager(address(crowdloanProxy));

        // algm.mint(address(vestingProxy), 1e36 ether);

        console.log("vesting:", address(vestingProxy));
        console.log("crowdloan:", address(crowdloanProxy));
        console.log("dappsStaking:", address(dappsStaking));
        // console.log("aastr:", address(aastr));
        // console.log("algm:", address(algm));

        vm.stopBroadcast();
    }
}

// == Logs == ASTAR
//   vesting: 0x4F802625E02907b2CF0409a35288617e5CB7C762
//   crowdloan: 0x59d3313feaa20555d84d6fBAb4652D267BE2a552
//   dappsStaking: 0x4aA6dA75F9deed62c76A7BC33e570a5Fb3033496

// == Logs ==
//   vesting: 0x1fA02b2d6A771842690194Cf62D91bdd92BfE28d
//   crowdloan: 0xdbC43Ba45381e02825b14322cDdd15eC4B3164E6
//   dappsStaking: 0x5081a39b8A5f0E35a8D959395a630b68B74Dd30f
//   aastr: 0x922D6956C99E12DFeB3224DEA977D0939758A1Fe
//   algm: 0x162A433068F51e18b7d13932F27e66a3f99E6890