// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/Pinkchainsaw.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployScript is Script {
    function run() external {
        address bzzToken = vm.envAddress("BZZ_TOKEN");
        address postageStamp = vm.envAddress("POSTAGE_STAMP");

        vm.startBroadcast();

        // 1. Deploy implementation
        Pinkchainsaw impl = new Pinkchainsaw();

        // 2. Deploy proxy with initialize call
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeCall(Pinkchainsaw.initialize, (bzzToken, postageStamp))
        );

        vm.stopBroadcast();

        console.log("Implementation:", address(impl));
        console.log("Proxy:", address(proxy));
    }
}
