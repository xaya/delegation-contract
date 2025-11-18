// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "./JsonSubObject.sol";

/**
 * @dev Simple wrapper contract around the JsonSubObject library so we can call
 * its internal logic from unit tests.
 */
contract JsonSubObjectTestHelper
{

  function atPath (string[] memory path, string memory subObject)
      public pure returns (string memory)
  {
    return JsonSubObject.atPath (path, subObject);
  }

}
