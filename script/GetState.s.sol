// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/LiquidCrowdloan.sol";
import "../src/ALGMVesting.sol";

interface Getter {
    function get() external view returns (uint256,uint256,uint256,uint256);
}

contract GetState is Script {
    LiquidCrowdloan cl;
    ALGMVesting vesting;
    IERC20 algm;
    IERC20 aastr;
    IERC20 nastr;
    Getter getter;

    function setUp() public {
        vesting = ALGMVesting(payable(0x4F802625E02907b2CF0409a35288617e5CB7C762));
        cl = LiquidCrowdloan(
            payable(0x59d3313feaa20555d84d6fBAb4652D267BE2a552)
        );
        algm = IERC20(0xFFfFFFFF00000000000000000000000000000530);
        aastr = IERC20(0xffFffffF0000000000000000000000000000052E);
        nastr = IERC20(0xE511ED88575C57767BAfb72BfD10775413E3F2b0);
        getter = Getter(0xc9bAb9751C1976A909CB4b4b98066ec65bb6873b);
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        (
            uint256 vestingALGMBalance,
            uint256 clALGMBalance,
            uint256 vestingAASTRBalance,
            uint256 clAASTRBalance
        ) = getter.get();

        console.log("Vesting's ALGM:", vestingALGMBalance);
        console.log("CrowdLoan's ALGM:", clALGMBalance);
        console.log("Vesting's aASTR:", vestingAASTRBalance);
        console.log("CrowdLoan's aASTR:", clAASTRBalance);

        vm.stopBroadcast();
    }
}
