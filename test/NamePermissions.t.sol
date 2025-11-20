// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import { addressArray, stringArray } from "./TestUtils.sol";
import "../src/NamePermissions.sol";

import { Test } from "forge-std/Test.sol";

contract NamePermissionsTest is Test
{

  /** @dev The contract instance we use for the test.  */
  NamePermissions internal np;

  function setUp () public
  {
    np = new NamePermissions ();
  }

  /**
   * @dev Grants a given permission.  This sends the transaction from the
   * desired owner, so that it will always go through.  This helper method
   * can be used in tests where not the granting itself is under test, but
   * the permissions are needed for other tests.
   */
  function grant (uint256 tokenId, address owner, string[] memory path,
                  address operator, uint256 expiration, bool fallbackOnly)
      internal
  {
    vm.prank (owner);
    np.grant (tokenId, owner, path, operator, expiration, fallbackOnly);
  }

  function test_readingState () public
  {
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (4), 100, true);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (2), 42, false);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (3), 50, false);
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (1), 200, false);
    grant (2, vm.addr (2), stringArray (), vm.addr (3), 100, true);

    vm.assertTrue (np.permissionExists (1, vm.addr (1), stringArray ("g")));
    vm.assertFalse (np.permissionExists (1, vm.addr (1),
                                          stringArray ("g", "id", "bar")));
    vm.assertFalse (np.permissionExists (2, vm.addr (1), stringArray ()));
    vm.assertTrue (np.permissionExists (2, vm.addr (2), stringArray ()));

    vm.assertTrue (np.permissionExists (2, vm.addr (2), stringArray (),
                                        vm.addr (3), true));
    vm.assertFalse (np.permissionExists (2, vm.addr (2), stringArray ("g"),
                                         vm.addr (3), true));
    vm.assertFalse (np.permissionExists (2, vm.addr (2), stringArray (),
                                         vm.addr (4), true));
    vm.assertFalse (np.permissionExists (2, vm.addr (2), stringArray (),
                                         vm.addr (3), false));
    vm.assertFalse (np.permissionExists (2, vm.addr (1), stringArray (),
                                         vm.addr (1), false));

    vm.assertEq (np.getExpiration (1, vm.addr (1), stringArray ("g", "id"),
                                   vm.addr (2), false), 42);
    vm.assertEq (np.getExpiration (1, vm.addr (1), stringArray ("g", "id"),
                                   vm.addr (2), true), 0);
    vm.assertEq (np.getExpiration (1, vm.addr (1), stringArray ("g", "id"),
                                   vm.addr (4), true), 100);
    vm.assertEq (np.getExpiration (2, vm.addr (2), stringArray ("g"),
                                   vm.addr (3), true), 0);
    vm.assertEq (np.getExpiration (2, vm.addr (1), stringArray (),
                                   vm.addr (1), true), 0);
    vm.assertEq (np.getExpiration (3, vm.addr (2), stringArray (),
                                   vm.addr (1), false), 0);

    (string[] memory children,
     address[] memory fullAccess,
     address[] memory fallbackAccess)
        = np.getDefinedKeys (1, vm.addr (1), stringArray ("g", "id"));
    vm.assertEq (children, stringArray ());
    vm.assertEq (fullAccess, addressArray (vm.addr (2), vm.addr (3)));
    vm.assertEq (fallbackAccess, addressArray (vm.addr (4)));

    (children, fullAccess, fallbackAccess)
        = np.getDefinedKeys (1, vm.addr (1), stringArray ("g"));
    vm.assertEq (children, stringArray ("id"));
    vm.assertEq (fullAccess, addressArray (vm.addr (1)));
    vm.assertEq (fallbackAccess, addressArray ());

    (children, fullAccess, fallbackAccess)
        = np.getDefinedKeys (3, vm.addr (1), stringArray ("g"));
    vm.assertEq (children, stringArray ());
    vm.assertEq (fullAccess, addressArray ());
    vm.assertEq (fallbackAccess, addressArray ());
  }

  function test_checkAccess () public
  {
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (2), 10, true);
    grant (2, vm.addr (2), stringArray (), vm.addr (3), 10, false);

    vm.assertTrue (np.hasAccess (1, vm.addr (1), stringArray ("g", "id"),
                                 vm.addr (1), 1000));
    vm.assertFalse (np.hasAccess (1, vm.addr (1), stringArray ("g", "id"),
                                  vm.addr (2), 10));
    vm.assertTrue (np.hasAccess (1, vm.addr (1),
                                 stringArray ("g", "id", "bar"),
                                 vm.addr (2), 10));

    vm.assertTrue (np.hasAccess (2, vm.addr (2), stringArray ("foo"),
                                 vm.addr (2), 1000));
    vm.assertTrue (np.hasAccess (2, vm.addr (2), stringArray ("foo"),
                                 vm.addr (3), 10));
    vm.assertFalse (np.hasAccess (2, vm.addr (2), stringArray ("foo"),
                                  vm.addr (3), 11));

    vm.assertTrue (np.hasAccess (2, vm.addr (1), stringArray ("foo"),
                                 vm.addr (1), 1000));
    vm.assertFalse (np.hasAccess (2, vm.addr (1), stringArray ("foo"),
                                  vm.addr (3), 1));
    vm.assertTrue (np.hasAccess (3, vm.addr (1), stringArray ("foo"),
                                 vm.addr (1), 1000));
    vm.assertFalse (np.hasAccess (3, vm.addr (1), stringArray ("foo"),
                                  vm.addr (3), 1));
  }

  function test_grant () public
  {
    /* We can start to seed permissions by the owner themselves, but later
       on, also people with permissions (including fallback permissions)
       can grant more.  */
    vm.prank (vm.addr (1));
    np.grant (1, vm.addr (1), stringArray (), vm.addr (2), 1000, true);
    vm.prank (vm.addr (2));
    np.grant (1, vm.addr (1), stringArray ("foo"), vm.addr (3), 100, false);
    vm.prank (vm.addr (2));
    np.grant (1, vm.addr (1), stringArray ("bar"), vm.addr (3), 100, false);

    vm.expectRevert ("the sender has no access");
    vm.prank (vm.addr (2));
    np.grant (2, vm.addr (1), stringArray (), vm.addr (2), 10, false);

    vm.expectRevert ("the sender has no access");
    vm.prank (vm.addr (2));
    np.grant (1, vm.addr (1), stringArray ("foo"), vm.addr (4), 10, false);

    vm.expectRevert ("the sender has no access");
    vm.prank (vm.addr (3));
    np.grant (1, vm.addr (1), stringArray ("foo"), vm.addr (4), 101, false);
  }

  function test_revoke () public
  {
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (2), 100, true);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (3),
           type (uint256).max, false);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (4),
           type (uint256).max, true);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (5), 10, false);

    /* Someone with only fallback permission can never revoke.  */
    vm.expectRevert ("the sender has no access");
    vm.prank (vm.addr (4));
    np.revoke (1, vm.addr (1), stringArray ("g", "id"), vm.addr (3), false);

    /* Someone with limited-in-time permission cannot revoke.  */
    vm.expectRevert ("the sender has no access");
    vm.prank (vm.addr (5));
    np.revoke (1, vm.addr (1), stringArray ("g", "id"), vm.addr (3), false);

    /* Some with unlimited access can revoke.  */
    vm.prank (vm.addr (3));
    np.revoke (1, vm.addr (1), stringArray ("g", "id"), vm.addr (5), false);
    /* The owner themselves can always revoke.  */
    vm.prank (vm.addr (1));
    np.revoke (1, vm.addr (1), stringArray ("g", "id"), vm.addr (3), false);
    /* The operator address can revoke its own permissions.  */
    vm.prank (vm.addr (4));
    np.revoke (1, vm.addr (1), stringArray ("g", "id"), vm.addr (4), true);
    vm.prank (vm.addr (2));
    np.revoke (1, vm.addr (1), stringArray ("g"), vm.addr (2), true);

    vm.assertFalse (np.permissionExists (1, vm.addr (1), stringArray ()));

    /* The operator and owner can revoke permissions even if they don't
       exist (i.e. it succeeds but won't have any effect).  */
    vm.prank (vm.addr (1));
    np.revoke (1, vm.addr (1), stringArray (), vm.addr (2), false);
    vm.prank (vm.addr (2));
    np.revoke (1, vm.addr (1), stringArray (), vm.addr (2), false);
  }

  function test_resetTree () public
  {
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (2),
           type (uint256).max, false);
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (3), 10, false);
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (3),
           type (uint256).max, true);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (4), 10, false);
    grant (1, vm.addr (1), stringArray ("g", "id"), vm.addr (4),
           type (uint256).max, true);

    /* Someone with fallback access or time-limited access cannot reset
       a subtree (as that would give them full access).  */
    vm.expectRevert ("the sender has no access");
    vm.prank (vm.addr (3));
    np.resetTree (1, vm.addr (1), stringArray ("g", "id"));

    /* Resetting a non-existing node (but with access permissions) should
       work fine.  It does nothing for the owner, and actually creates a new
       permission entry for a non-owner.  */
    vm.prank (vm.addr (1));
    np.resetTree (1, vm.addr (1), stringArray ("g", "foo"));
    vm.assertFalse (
        np.permissionExists (1, vm.addr (1), stringArray ("g", "foo")));
    vm.prank (vm.addr (2));
    np.resetTree (1, vm.addr (1), stringArray ("g", "foo"));
    vm.assertTrue (
        np.permissionExists (1, vm.addr (1), stringArray ("g", "foo")));

    /* Test resetting an existing node, which should clean out the subtree.
       The sender will keep access.  */
    vm.prank (vm.addr (2));
    np.resetTree (1, vm.addr (1), stringArray ("g"));
    vm.assertTrue (np.permissionExists (1, vm.addr (1), stringArray ("g")));
    vm.assertFalse (
        np.permissionExists (1, vm.addr (1), stringArray ("g", "foo")));
    vm.assertFalse (
        np.permissionExists (1, vm.addr (1), stringArray ("g", "id")));
    vm.assertTrue (np.hasAccess (1, vm.addr (1), stringArray ("g"),
                                 vm.addr (2), type (uint256).max));

    /* If the owner themselves resets, it will remove empty nodes as well.  */
    vm.prank (vm.addr (1));
    np.resetTree (1, vm.addr (1), stringArray ());
    vm.assertFalse (np.permissionExists (1, vm.addr (1), stringArray ()));
    vm.assertTrue (np.hasAccess (1, vm.addr (1), stringArray (),
                                 vm.addr (1), type (uint256).max));
  }

  function test_expireTree () public
  {
    uint256 start = block.timestamp;

    grant (1, vm.addr (1), stringArray (), vm.addr (2), start + 100, false);
    grant (1, vm.addr (1), stringArray (), vm.addr (3), start + 100, true);
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (3), start + 100, true);
    grant (1, vm.addr (1), stringArray ("g"), vm.addr (4), start + 200, false);

    /* Nothing is expired yet.  */
    vm.prank (vm.addr (5));
    np.expireTree (1, vm.addr (1), stringArray ());
    vm.assertTrue (np.permissionExists (1, vm.addr (1), stringArray ("g"),
                                        vm.addr (3), true));
    vm.assertTrue (np.permissionExists (1, vm.addr (1), stringArray ("g"),
                                        vm.addr (4), false));

    /* Some entries are expired, but also only those will be evaluated that
       we expire explicitly.  */
    vm.warp (start + 150);
    vm.prank (vm.addr (5));
    np.expireTree (1, vm.addr (1), stringArray ("g"));
    vm.assertFalse (np.permissionExists (1, vm.addr (1), stringArray ("g"),
                                         vm.addr (3), true));
    vm.assertTrue (np.permissionExists (1, vm.addr (1), stringArray ("g"),
                                        vm.addr (4), false));

    /* Expire the entire "g" tree.  Note that this can cause fallback
       permissions to "increase" in scope.  */
    vm.assertFalse (
        np.hasAccess (1, vm.addr (1), stringArray ("g"), vm.addr (3), 1));
    vm.warp (start + 250);
    vm.prank (vm.addr (5));
    np.expireTree (1, vm.addr (1), stringArray ("g"));
    vm.assertFalse (np.permissionExists (1, vm.addr (1), stringArray ("g")));
    vm.assertTrue (
        np.hasAccess (1, vm.addr (1), stringArray ("g"), vm.addr (3), 1));

    /* Expire the entire tree.  */
    np.expireTree (1, vm.addr (1), stringArray ());
    vm.assertFalse (np.permissionExists (1, vm.addr (1), stringArray ()));
    vm.assertFalse (
        np.hasAccess (1, vm.addr (1), stringArray ("g"), vm.addr (3), 1));
  }

}
