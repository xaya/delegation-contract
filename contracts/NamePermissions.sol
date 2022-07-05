// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "./MovePermissions.sol";

import "@openzeppelin/contracts/utils/Context.sol";

/**
 * @dev A base smart contract that stores a tree of move permissions for
 * each token ID of a Xaya name, and NFT owner.  It also implements basic
 * methods to extract the data via public view methods if desired, and
 * to modify (grant and revoke) permissions.  These methods will ensure
 * proper authorisation checks, so that only users actually permitted
 * to grant or revoke permissions can do so.
 *
 * This contract is still "abstract" in that it does not actually link
 * to the XayaAccounts registry yet (and thus does not actually query
 * or process who really owns a name at the moment), and it also does not
 * yet implement actual move functions (just the permissions handling).
 */
contract NamePermissions is Context
{

  using MovePermissions for MovePermissions.PermissionsNode;

  /* ************************************************************************ */

  /**
   * @dev The permissions tree associated to each particular name when
   * owned by a given account.
   */
  mapping (uint256 => mapping (address => MovePermissions.PermissionsNode))
      private permissions;

  /** @dev Event fired when a permission is granted.  */
  event PermissionGranted (uint256 indexed tokenId, address indexed owner,
                           string[] path, address operator, uint256 expiration,
                           bool fallbackOnly);

  /**
   * @dev Event fired when a particular permission is revoked.  Note that this
   * may or may not mean that some empty nodes in the permissions tree
   * have been pruned as well.
   */
  event PermissionRevoked (uint256 indexed tokenId, address indexed owner,
                           string[] path, address operator, bool fallbackOnly);

  /**
   * @dev Event fired when an entire tree of permissions has been reset
   * to just a single permission (for the message sender).
   */
  event PermissionTreeReset (uint256 indexed tokenId, address indexed owner,
                             string[] path);

  /**
   * @dev Event fired when permissions inside a subtree have been explicitly
   * expired.  Note that the individual permissions removed do not emit
   * any more events.
   */
  event PermissionTreeExpired (uint256 indexed tokenId, address indexed owner,
                               string[] path, uint256 atTime);

  /* ************************************************************************ */

  /**
   * @dev Retrieves the permissions node at the given position.
   */
  function retrieve (uint256 tokenId, address owner, string[] memory path)
      private view returns (MovePermissions.PermissionsNode storage)
  {
    return permissions[tokenId][owner].retrieveNode (path);
  }

  /**
   * @dev Retrieves the address permissions tied to a given place in the
   * permissions hierarchy, operator and fallback status.
   */
  function retrieve (uint256 tokenId, address owner, string[] memory path,
                     address operator, bool fallbackOnly)
      private view returns (MovePermissions.AddressPermissions storage)
  {
    MovePermissions.PermissionsNode storage node
        = retrieve (tokenId, owner, path);
    return (fallbackOnly ? node.fallbackAccess.forAddress[operator]
                         : node.fullAccess.forAddress[operator]);
  }

  /**
   * @dev Returns true if there is a node with specific permissions
   * at the given hierarchy level (i.e. it exists).
   */
  function permissionExists (uint256 tokenId, address owner,
                             string[] memory path)
      public view returns (bool)
  {
    return retrieve (tokenId, owner, path).indexAndOne != 0;
  }

  /**
   * @dev Returns true if a specific permission exists at the given
   * node and for the given operator and fallback type.
   */
  function permissionExists (uint256 tokenId, address owner,
                             string[] memory path, address operator,
                             bool fallbackOnly)
      public view returns (bool)
  {
    MovePermissions.AddressPermissions storage addrPerm
        = retrieve (tokenId, owner, path, operator, fallbackOnly);
    return addrPerm.indexAndOne != 0;
  }

  /**
   * @dev Returns the expiration timestamp for a given operator permission
   * inside the storage.
   */
  function getExpiration (uint256 tokenId, address owner, string[] memory path,
                          address operator, bool fallbackOnly)
      public view returns (uint256)
  {
    MovePermissions.AddressPermissions storage addrPerm
        = retrieve (tokenId, owner, path, operator, fallbackOnly);
    return addrPerm.expiration;
  }

  /**
   * @dev Returns all defined keys (addresses with full access, addresses
   * with fallback access, and child paths) for the node at the given position
   * in the permissions.
   */
  function getDefinedKeys (uint256 tokenId, address owner, string[] memory path)
      public view returns (string[] memory children,
                           address[] memory fullAccess,
                           address[] memory fallbackAccess)
  {
    MovePermissions.PermissionsNode storage node
        = retrieve (tokenId, owner, path);
    children = node.keys;
    fullAccess = node.fullAccess.keys;
    fallbackAccess = node.fallbackAccess.keys;
  }

  /* ************************************************************************ */

  /**
   * @dev Checks if the given address has access permissions to the
   * given token and hierarchy level.  In addition to the actual rules
   * specified in the permissions themselves, the owner address always
   * has access.
   */
  function hasAccess (uint256 tokenId, address owner, string[] memory path,
                      address operator, uint256 atTime)
      public view returns (bool)
  {
    if (operator == owner)
      return true;

    return permissions[tokenId][owner].check (path, operator, atTime);
  }

  /**
   * @dev Tries to grant a particular permission, checking that the sender
   * of the message is actually allowed to do so.
   */
  function grant (uint256 tokenId, address owner, string[] memory path,
                  address operator, uint256 expiration, bool fallbackOnly)
      public
  {
    require (hasAccess (tokenId, owner, path, _msgSender (), expiration),
             "the sender has no access");

    permissions[tokenId][owner].grant (path, operator,
                                       expiration, fallbackOnly);
    emit PermissionGranted (tokenId, owner, path, operator,
                            expiration, fallbackOnly);
  }

  /**
   * @dev Checks if the root node for the given token and owner is empty
   * (i.e. potentially set but with nothing in it) and removes it if so.
   */
  function removeIfEmpty (uint256 tokenId, address owner) private
  {
    MovePermissions.PermissionsNode storage root = permissions[tokenId][owner];
    if (root.indexAndOne != 0 && root.isEmpty ())
      delete permissions[tokenId][owner];
  }

  /**
   * @dev Revokes a particular approval, checking that the message
   * sender is actually allowed to do so.
   */
  function revoke (uint256 tokenId, address owner, string[] memory path,
                   address operator, bool fallbackOnly)
      public
  {
    address sender = _msgSender ();
    /* Any address can revoke its own access, and also any access on levels
       where it has unlimited (in time) permissions.  */
    require (sender == operator
                || hasAccess (tokenId, owner, path, sender, type (uint256).max),
             "the sender has no access");

    permissions[tokenId][owner].revoke (path, operator, fallbackOnly);
    removeIfEmpty (tokenId, owner);
    emit PermissionRevoked (tokenId, owner, path, operator, fallbackOnly);
  }

  /**
   * @dev Revokes all permissions in a given subtree, and replaces them with
   * just a single permission for the message sender.  This can be used
   * to reset an entire tree of permissions if desired, while making sure the
   * message sender retains permission (but they can explicitly revoke their
   * own as well afterwards).  Reverts if the message sender has no access
   * to the requested level.
   */
  function resetTree (uint256 tokenId, address owner, string[] memory path)
      public
  {
    address sender = _msgSender ();
    require (hasAccess (tokenId, owner, path, sender, type (uint256).max),
             "the sender has no access");

    MovePermissions.PermissionsNode storage root = permissions[tokenId][owner];
    root.revokeTree (path);

    /* If the message sender is not the owner, we add them back as only
       permission at that level now (and then the subtree is by definition
       not empty).  Otherwise, they have access in any case, and we might
       be able to prune an empty tree.  */
    if (sender != owner)
      root.grant (path, sender, type (uint256).max, false);
    else
      removeIfEmpty (tokenId, owner);

    emit PermissionTreeReset (tokenId, owner, path);
  }

  /**
   * @dev Removes all expired permissions in the given subtree.  This may
   * have an indirect effect on fallback permissions, but otherwise does not
   * alter permissions (since it only removes ones that are expired anyway at
   * the current time).  Everyone is allowed to call this if they are willing
   * to pay for the gas.
   */
  function expireTree (uint256 tokenId, address owner, string[] memory path)
      public
  {
    permissions[tokenId][owner].expireTree (path, block.timestamp);
    removeIfEmpty (tokenId, owner);
    emit PermissionTreeExpired (tokenId, owner, path, block.timestamp);
  }

  /* ************************************************************************ */

}
