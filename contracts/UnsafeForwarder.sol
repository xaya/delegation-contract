// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

/**
 * @dev Simple forwarding contract for ERC2771 testing.  This does not
 * verify anything, and just forwards every call directly.
 *
 * DO NOT USE IN PRODUCTION!
 */
contract UnsafeForwarder
{

  /**
   * @dev Forwards a call to the "to" contract with the given calldata
   * and "from", encoded as per ERC2771.  This method does no checks
   * and is intended only for testing!
   */
  function exec (address to, bytes calldata data, address from)
      external
  {
    (bool ok, bytes memory ret) = to.call (abi.encodePacked (data, from));
    require (ok, string (abi.encodePacked ("forwarded call reverted: ", ret)));
  }

}
