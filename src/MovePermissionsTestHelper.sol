// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "./MovePermissions.sol";

/**
 * @dev Simple wrapper contract around the MovePermissions library so we can
 * call its internal logic from unit tests.
 */
contract MovePermissionsTestHelper
{

  /** @dev The permissions tree used in testing.  */
  MovePermissions.PermissionsNode internal root;

  /**
   * @dev Retrieves a node by path, not creating anything (so this is
   * purely read-only).
   */
  function retrieve (string[] memory path)
      internal view returns (MovePermissions.PermissionsNode storage)
  {
    return MovePermissions.retrieveNode (root, path);
  }

  /**
   * @dev Returns the key arrays in a given node, so the test can
   * compare that to what is expected.
   */
  function getKeys (string[] memory path)
      public view returns (string[] memory, address[] memory, address[] memory)
  {
    MovePermissions.PermissionsNode storage node = retrieve (path);
    return (node.keys, node.fullAccess.keys, node.fallbackAccess.keys);
  }

  /**
   * @dev Returns the configured expiration timestamp for the
   * given operator in a node (both for full access and fallback).
   */
  function getTimestamps (string[] memory path, address operator)
      public view returns (uint256, uint256)
  {
    MovePermissions.PermissionsNode storage node = retrieve (path);
    return (node.fullAccess.forAddress[operator].expiration,
            node.fallbackAccess.forAddress[operator].expiration);
  }

  /**
   * @dev Checks if a node is empty / unset.
   */
  function isEmpty (string[] memory path) public view returns (bool)
  {
    return retrieve (path).indexAndOne == 0;
  }

  function check (string[] memory path, address operator, uint256 atTime)
      public view returns (bool)
  {
    return MovePermissions.check (root, path, operator, atTime);
  }

  function grant (string[] memory path, address operator, uint256 expiration,
                  bool fallbackOnly) public
  {
    MovePermissions.grant (root, path, operator, expiration, fallbackOnly);
  }

  function revoke (string[] memory path, address operator, bool fallbackOnly)
      public
  {
    MovePermissions.revoke (root, path, operator, fallbackOnly);
  }

  function revokeTree (string[] memory path) public
  {
    MovePermissions.revokeTree (root, path);
  }

  function expireTree (string[] memory path, uint256 atTime) public
  {
    MovePermissions.expireTree (root, path, atTime);
  }

}
