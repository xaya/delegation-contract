// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import { addressArray, stringArray } from "./TestUtils.sol";
import "../src/MovePermissions.sol";

import { Test } from "forge-std/Test.sol";

contract MovePermissionsTest is Test
{

  /** @dev The permissions tree used in testing.  */
  MovePermissions.PermissionsNode internal root;

  /**
   * @dev Expects that the keys present on a given node match
   * the given arrays of children and addresses with direct or fallback
   * access.
   */
  function expectKeys (string[] memory path, string[] memory children,
                       address[] memory access, address[] memory fallb)
      internal view
  {
    MovePermissions.PermissionsNode storage node
        = MovePermissions.retrieveNode (root, path);
    vm.assertEq (node.keys, children);
    vm.assertEq (node.fullAccess.keys, access);
    vm.assertEq (node.fallbackAccess.keys, fallb);
  }

  /**
   * @dev Expects that the timestamps present for a given node
   * match the given arrays (for full access and fallback access).
   */
  function expectTimestamps (string[] memory path, address operator,
                             uint access, uint fallb)
      internal view
  {
    MovePermissions.PermissionsNode storage node
        = MovePermissions.retrieveNode (root, path);
    vm.assertEq (node.fullAccess.forAddress[operator].expiration, access);
    vm.assertEq (node.fallbackAccess.forAddress[operator].expiration, fallb);
  }

  /**
   * @dev Checks if a node is empty / unset.
   */
  function isEmpty (string[] memory path)
      internal view returns (bool)
  {
    return MovePermissions.retrieveNode (root, path).indexAndOne == 0;
  }

  /* Define external helper functions (using our root node) for the library
     functions, so that vm.expectRevert properly works without having to
     enable it for internal calls (which has other issues).  */

  function check (string[] memory path, address operator, uint256 atTime)
      public view returns (bool)
  {
    return MovePermissions.check (root, path, operator, atTime);
  }

  function grant (string[] memory path, address operator, uint256 expiration,
                  bool fallbackOnly)
      public
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

  /* ************************************************************************ */

  function test_grant () public
  {
    grant (stringArray (), address (0), type (uint256).max, true);
    grant (stringArray ("g", "id"), address (1), type (uint256).max, false);
    grant (stringArray ("g", "id"), address (2), 100, false);
    grant (stringArray ("g", "id"), address (2), 100, false);
    grant (stringArray ("g", "id"), address (2), 101, false);

    vm.expectRevert ("cannot grant permissions with zero expiration");
    this.grant (stringArray (), address (0), 0, false);
    vm.expectRevert ("existing permission has longer validity than new grant");
    this.grant (stringArray ("g", "id"), address (2), 90, false);

    vm.assertFalse (isEmpty (stringArray ()));
    vm.assertFalse (isEmpty (stringArray ("g")));
    vm.assertFalse (isEmpty (stringArray ("g", "id")));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo")));
    vm.assertTrue (isEmpty (stringArray ("g", "tn")));

    expectKeys (stringArray (), stringArray ("g"),
                addressArray (), addressArray (address (0)));
    expectKeys (stringArray ("g"), stringArray ("id"),
                addressArray (), addressArray ());
    expectKeys (stringArray ("g", "id"), stringArray (),
                addressArray (address (1), address (2)), addressArray ());
    expectKeys (stringArray ("g", "id", "foo"), stringArray (),
                addressArray (), addressArray ());

    expectTimestamps (stringArray (), address (0), 0, type (uint256).max);
    expectTimestamps (stringArray (), address (1), 0, 0);
    expectTimestamps (stringArray ("g", "id"), address (1),
                      type (uint256).max, 0);
    expectTimestamps (stringArray ("g", "id"), address (2), 101, 0);
  }

  function test_check () public
  {
    grant (stringArray ("g"), address (0), type (uint256).max, true);
    grant (stringArray ("g", "id"), address (1), 200, false);

    vm.expectRevert ("atTime must not be zero");
    this.check (stringArray (), address (0), 0);

    vm.assertFalse (check (stringArray (), address (0), 1));
    vm.assertFalse (check (stringArray ("g"), address (0), 1));
    vm.assertTrue (check (stringArray ("g", "foo"), address (0),
                          type (uint256).max));

    vm.assertFalse (check (stringArray (), address (1), 1));
    vm.assertFalse (check (stringArray ("x"), address (1), 1));
    vm.assertTrue (check (stringArray ("g", "id"), address (1), 200));
    vm.assertFalse (check (stringArray ("g", "id"), address (1), 201));
    vm.assertFalse (check (stringArray ("g", "id"),
                           address (1), type (uint256).max));
    vm.assertTrue (check (stringArray ("g", "id", "foo"), address (1), 200));
  }

  function test_revoke () public
  {
    grant (stringArray ("g", "id"), address (0), type (uint256).max, true);
    grant (stringArray ("g", "id", "first"), address (1),
           type (uint256).max, false);
    grant (stringArray ("g", "id", "foo", "bar"), address (1), 1, false);
    grant (stringArray ("g", "id", "foo", "bar"), address (2), 2, false);
    grant (stringArray ("g", "id", "foo", "bar"), address (3), 3, false);
    grant (stringArray ("g", "id", "foo", "bar"), address (1), 4, true);

    /* Revoking a non-existing permission is fine and just doesn't do
       anything.  Same for a non-existing node path.  */
    revoke (stringArray ("g", "id", "foo", "bar"), address (4), true);
    revoke (stringArray ("g", "id", "foo", "bar", "baz"), address (1), false);

    /* Revoke permissions and remove a child node from within the list.  */
    vm.assertTrue (check (stringArray ("g", "id", "first"), address (1), 1));
    vm.assertFalse (isEmpty (stringArray ("g", "id", "first")));
    expectKeys (stringArray ("g", "id"), stringArray ("first", "foo"),
                addressArray (), addressArray (address (0)));
    revoke (stringArray ("g", "id", "first"), address (1), false);
    vm.assertFalse (check (stringArray ("g", "id", "first"), address (1), 1));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "first")));
    expectKeys (stringArray ("g", "id"), stringArray ("foo"),
                addressArray (), addressArray (address (0)));

    /* Revoke the permissions again, making sure to remove them both
       from the "end" of the list and from the middle.  */
    revoke (stringArray ("g", "id", "foo", "bar"), address (3), false);
    expectKeys (stringArray ("g", "id", "foo", "bar"), stringArray (),
                addressArray (address (1), address (2)),
                addressArray (address (1)));
    expectTimestamps (stringArray ("g", "id", "foo", "bar"), address (1),
                      1, 4);
    revoke (stringArray ("g", "id", "foo", "bar"), address (1), true);
    expectTimestamps (stringArray ("g", "id", "foo", "bar"), address (1),
                      1, 0);
    expectKeys (stringArray ("g", "id", "foo", "bar"), stringArray (),
                addressArray (address (1), address (2)), addressArray ());
    revoke (stringArray ("g", "id", "foo", "bar"), address (1), false);
    expectKeys (stringArray ("g", "id", "foo", "bar"), stringArray (),
                addressArray (address (2)), addressArray ());
    expectTimestamps (stringArray ("g", "id", "foo", "bar"), address (2),
                      2, 0);
    vm.assertFalse (isEmpty (stringArray ("g", "id", "foo", "bar")));

    /* In the current set up, the fallback permission at g/id does
       not apply too foo.  */
    vm.assertFalse (check (stringArray ("g", "id", "foo"), address (0), 1));

    /* Revoke the last permission at the node, and it will be removed
       together with all other empty parent nodes.  */
    revoke (stringArray ("g", "id", "foo", "bar"), address (2), false);
    expectKeys (stringArray ("g", "id", "foo", "bar"), stringArray (),
                addressArray (), addressArray ());
    expectKeys (stringArray ("g", "id"), stringArray (),
                addressArray (), addressArray (address (0)));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo", "bar")));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo")));
    vm.assertFalse (isEmpty (stringArray ("g", "id")));

    /* Now the fallback access will be enabled again.  */
    vm.assertTrue (check (stringArray ("g", "id", "foo"), address (0), 1));

    /* Remove the last permission, cleaning out the entire tree.  */
    revoke (stringArray ("g", "id"), address (0), true);
    vm.assertTrue (isEmpty (stringArray ("g", "id")));
    vm.assertTrue (isEmpty (stringArray ("g")));
    /* The root node will not be considered completely empty according to
       our function definition in the test helper (since it exists), but
       it will have no contents.  */
    vm.assertFalse (isEmpty (stringArray ()));
    expectKeys (stringArray (), stringArray (), addressArray (),
                addressArray ());
  }

  function test_revokeTree () public
  {
    grant (stringArray ("g", "id"), address (0), 1, true);
    grant (stringArray ("g", "id", "foo"), address (1), 2, true);
    grant (stringArray ("g", "id", "foo", "bar"), address (2), 3, false);
    grant (stringArray ("g", "id", "foo", "bar"), address (2), 4, true);
    grant (stringArray ("g", "id", "foo", "bar"), address (3), 5, true);
    grant (stringArray ("g", "id", "foo", "baz"), address (2), 6, false);

    vm.assertTrue (check (stringArray ("g", "id", "foo", "bar"),
                          address (2), 1));
    revokeTree (stringArray ("g", "id", "foo"));
    vm.assertFalse (check (stringArray ("g", "id", "foo", "bar"),
                           address (2), 1));
    vm.assertFalse (isEmpty (stringArray ("g", "id", "foo")));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo", "bar")));
    expectKeys (stringArray ("g", "id"), stringArray ("foo"),
                addressArray (), addressArray (address (0)));
    expectKeys (stringArray ("g", "id", "foo"), stringArray (),
                addressArray (), addressArray ());

    vm.assertTrue (check (stringArray ("g", "id", "x"), address (0), 1));
    revokeTree (stringArray ());
    /* Revoking a non-existing tree is fine, too (and has no effect).  */
    revokeTree (stringArray ("a", "b", "c"));

    vm.assertFalse (check (stringArray ("g", "id", "x"), address (0), 1));
    vm.assertFalse (isEmpty (stringArray ()));
    vm.assertTrue (isEmpty (stringArray ("g")));
    vm.assertTrue (isEmpty (stringArray ("g", "id")));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo")));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo", "bar")));
    expectKeys (stringArray (), stringArray (),
                addressArray (), addressArray ());
    expectKeys (stringArray ("g", "id"), stringArray (),
                addressArray (), addressArray ());
  }

  function test_expireTree () public
  {
    grant (stringArray ("g", "id"), address (0), 2, true);
    grant (stringArray ("g", "id"), address (1), 2, false);
    grant (stringArray ("g", "id"), address (2), 3, false);
    grant (stringArray ("g", "id"), address (3), 2, false);
    grant (stringArray ("g", "id"), address (4), 3, false);
    grant (stringArray ("g", "id"), address (5), 2, false);
    grant (stringArray ("g", "id", "foo", "ba1"), address (0), 5, false);
    grant (stringArray ("g", "id", "foo", "ba2"), address (0), 20, false);
    grant (stringArray ("g", "id", "foo", "ba3"), address (0), 5, false);
    grant (stringArray ("g", "id", "foo", "ba4"), address (0), 20, false);
    grant (stringArray ("g", "id", "foo", "ba5"), address (0), 5, false);

    expireTree (stringArray ("g", "id", "foo"), 10);
    expectKeys (stringArray ("g", "id", "foo"), stringArray ("ba4", "ba2"),
                addressArray (), addressArray ());
    expireTree (stringArray ("g", "id", "foo"), 100);
    vm.assertFalse (isEmpty (stringArray ("g", "id")));
    vm.assertTrue (isEmpty (stringArray ("g", "id", "foo")));
    expectKeys (stringArray ("g", "id"), stringArray (),
                addressArray (address (1), address (2), address (3),
                              address (4), address (5)),
                addressArray (address (0)));

    vm.assertTrue (check (stringArray ("g", "id", "foo"), address (0), 1));
    expireTree (stringArray (), 3);
    vm.assertFalse (check (stringArray ("g", "id", "foo"), address (0), 1));
    expectKeys (stringArray ("g", "id"), stringArray (),
                addressArray (address (4), address (2)), addressArray ());
    expireTree (stringArray (), 10);
    /* Expiring an empty tree / path is fine.  */
    expireTree (stringArray ("foo", "bar"), 10);

    /* We should have expired everything (but that keeps the root node
       itself intact but empty).  */
    vm.assertTrue (isEmpty (stringArray ("g")));
    vm.assertFalse (isEmpty (stringArray ()));
    expectKeys (stringArray (), stringArray (),
                addressArray (), addressArray ());
  }

}
