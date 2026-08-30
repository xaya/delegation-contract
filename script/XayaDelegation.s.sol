// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "./PolygonConfig.sol";
import "../src/XayaDelegation.sol";

import { Script } from "forge-std/Script.sol";

/**
 * @dev This is the script to deploy the XayaDelegation contract.
 */
contract XayaDelegationScript is Script
{

  function run () public
  {
    uint256 privkey = vm.envUint ("PRIVKEY");

    vm.startBroadcast (privkey);
    new XayaDelegation (PolygonConfig.acc, PolygonConfig.fwd);
    vm.stopBroadcast ();
  }

}
