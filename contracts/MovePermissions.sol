// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

/**
 * @dev Solidity library that implements the core permissions logic for moves.
 * Those permissions form hierarchical trees (with one tree for a particular
 * account (token ID) and current owner).  The trees correspond to JSON "paths"
 * to specify which bits of a full move someone has permission for (e.g.
 * just the g->tn subobject to send Taurion moves, or even just a particular
 * type of move for one game).
 *
 * Each node in the tree can specify:
 *  - addresses that have permission for moves in that subtree,
 *    potentially with an expiration time
 *  - addresses that have "fallback permission" (with optional expiration),
 *    which means that have access to any subtree (not at the current level
 *    directly) that has no explicit node in the permissions tree
 *  - child nodes that further refine permissions for JSON fields
 *    below the current level
 *
 * This library implements the core logic for operating on these permission
 * trees, without actually triggering delegated moves nor even storing the
 * actual root trees themselves and tying them to accounts.  It just exposes
 * internal methods for querying and updating the permission trees passed in
 * as storage pointers.
 */
library MovePermissions
{

  /* ************************************************************************ */

  /**
   * @dev Helper struct which represents the data stored for an address
   * with (fallback) permissions.
   */
  struct AddressPermissions
  {

    /**
     * @dev The latest timestamp when permissions are granted, or uint256.max
     * if access is "unlimited".
     */
    uint256 expiration;

    /**
     * @dev The one-based index (i.e. the actual index + 1) of the address in
     * the parent struct's array of addresses with explicit permissions.
     *
     * This has two uses:  First, it allows us to explicitly and effectively
     * delete an entry and update the list of defined addresses at the same
     * time (by swap-replacing the entry at the given index with the last one
     * and shrinking the array).  Second, if the value is non-zero, we know that
     * the entry actually exists and is explicitly set (vs. zero meaning it
     * is a missing map entry).
     */
    uint indexAndOne;

  }

  /**
   * @dev A mapping of addresses to explicit permissions (mainly expiration
   * timestamps) of them.  This also contains book-keeping data so that
   * we can iterate through all explicit addresses and remove them if
   * so desired (as well as remove individual ones).
   */
  struct PermissionsMap
  {

    /** @dev Addresses and their associated permissions.  */
    mapping (address => AddressPermissions) forAddress;

    /** @dev List of all addresses with set permissions.  */
    address[] keys;

  }

  /**
   * @dev All data stored for permissions at a particular node in the
   * tree for one account.  This also contains necessary book-keeping data
   * to iterate the entire tree and remove all entries in it if desired.
   */
  struct PermissionsNode
  {

    /**
     * @dev The one-based index (i.e. actual index + 1) of this node
     * in the parent's "keys" array (similar to the field in
     * AddressPermissions).
     *
     * For the permissions at the tree's root, this value is just something
     * non-zero to indicate the entry actually exists.
     */
    uint indexAndOne;

    /** @dev Addresses that have full access at and below the current level.  */
    PermissionsMap fullAccess;

    /** @dev Addresses with fallback access only.  */
    PermissionsMap fallbackAccess;

    /** @dev Child nodes with explicitly defined permissions.  */
    mapping (string => PermissionsNode) children;

    /** @dev All keys for which child nodes are defined.  */
    string[] keys;

  }

  /* ************************************************************************ */

  /**
   * @dev Checks if the given address should have move permissions in a
   * particular permissions tree (whose root node is passed) for a particular
   * JSON path and at a particular time.  Returns true if permissions should
   * be granted and false if not.
   */
  function check (PermissionsNode storage root, string[] memory path,
                  address operator, uint256 atTime)
      internal view returns (bool)
  {
    /* For simplicity, we check "expiration >= atTime" later on against
       the permissions entries.  If an entry does not exist at all, expiration
       will be returned as zero.  This could lead to unexpected behaviour
       if we allow atTime to be zero.  Since a zero atTime is not relevant
       in practice anyway (since that is long in the past), let's explicitly
       disallow this.  */
    require (atTime > 0, "atTime must not be zero");

    PermissionsNode storage node = root;
    uint nextPath = 0;

    while (true)
      {
        /* If there is an explicit and non-expired full-access entry
           at the current level, we're good.  */
        if (node.fullAccess.forAddress[operator].expiration >= atTime)
          return true;

        /* We can't grant access directly at the current level.  So if the
           request is not for a deeper level, we reject it.  */
        assert (nextPath <= path.length);
        if (nextPath == path.length)
          return false;

        /* See if there is an explicit node for the next path level.
           If there is, we continue with it.  */
        PermissionsNode storage child = node.children[path[nextPath]];
        if (child.indexAndOne > 0)
          {
            node = child;
            ++nextPath;
            continue;
          }

        /* Finally, we apply access based on the fallback map.  */
        return node.fallbackAccess.forAddress[operator].expiration >= atTime;
      }

    /* We can never reach here, but this silences the compiler warning
       about a missing return.  */
    assert (false);
    return false;
  }

  /* ************************************************************************ */

  /**
   * @dev Looks up and returns (as storage pointer) the ultimate
   * tree node with the permissions for the given level.  If it (or any
   * of its parents) does not exist yet and "create" is set, those will be
   * added.
   */
  function retrieveNode (PermissionsNode storage root, string[] memory path,
                         bool create)
      private returns (PermissionsNode storage)
  {
    /* If the root itself does not actually exist (is not initialised yet),
       we do so as well.  For the root, the only thing that matters is
       that indexAndOne is not zero.  We set it to max uint256 just to emphasise
       it is not an actual, valid index.  */
    if (root.indexAndOne == 0 && create)
      root.indexAndOne = type (uint256).max;

    PermissionsNode storage node = root;
    for (uint i = 0; i < path.length; ++i)
      {
        PermissionsNode storage child = node.children[path[i]];

        /* If the node does not exist yet, add it explicitly to the parent's
           keys array, and store its indexAndOne.  */
        if (child.indexAndOne == 0 && create)
          {
            node.keys.push (path[i]);
            child.indexAndOne = node.keys.length;
          }

        node = child;
      }

    return node;
  }

  /**
   * @dev Looks up and returns (as storage pointer) the ultimate tree node
   * with the given level.  This method never auto-creates entries,
   * and is available to users of the library.  It is also "view".
   */
  function retrieveNode (PermissionsNode storage root, string[] memory path)
      internal view returns (PermissionsNode storage res)
  {
    res = root;
    for (uint i = 0; i < path.length; ++i)
      res = res.children[path[i]];
  }

  /**
   * @dev Sets the expiration timestamp associated to an address in a
   * permissions map to the given value.  This function also takes care to
   * update the necessary book-keeping fields (i.e. keys) in case this
   * actually inserts a new element.  Note that this is meant for granting
   * permissions, and as such the new timestamp must be non-zero and also
   * not earlier than any existing timestamp.
   */
  function setExpiration (PermissionsMap storage map, address key,
                          uint256 expiration) private
  {
    require (expiration > 0, "cannot grant permissions with zero expiration");

    AddressPermissions storage entry = map.forAddress[key];
    require (expiration >= entry.expiration,
             "existing permission has longer validity than new grant");
    entry.expiration = expiration;

    if (entry.indexAndOne == 0)
      {
        map.keys.push (key);
        entry.indexAndOne = map.keys.length;
      }
  }

  /**
   * @dev Unconditionally grants permissions in a given tree to a given
   * operator address, potentially in the fallback map.  The expiration time
   * must be non-zero and must not be earlier than any existing entry in the
   * given map.  No other checks are performed, so callers need to make sure
   * that it is actually permitted in the current context to grant the new
   * permission.
   */
  function grant (PermissionsNode storage root, string[] memory path,
                  address operator, uint256 expiration, bool fallbackOnly)
      internal
  {
    PermissionsNode storage node = retrieveNode (root, path, true);
    setExpiration (fallbackOnly ? node.fallbackAccess : node.fullAccess,
                   operator, expiration);
  }

  /* ************************************************************************ */

  /**
   * @dev Revokes permissions for an address in a PermissionsMap (i.e. removes
   * the corresponding entry, keeping "keys" up-to-date).
   */
  function removeEntry (PermissionsMap storage map, address key) private
  {
    uint oldIndex = map.forAddress[key].indexAndOne;
    if (oldIndex == 0)
      return;

    delete map.forAddress[key];

    /* Now we need to remove the entry from keys.  If it is the last one,
       we can just pop.  Otherwise we swap the last element into its position
       and pop then.  */

    if (oldIndex < map.keys.length)
      {
        address last = map.keys[map.keys.length - 1];
        map.keys[oldIndex - 1] = last;

        AddressPermissions storage lastEntry = map.forAddress[last];
        assert (lastEntry.indexAndOne > 0);
        lastEntry.indexAndOne = oldIndex;
      }

    map.keys.pop ();
  }

  /**
   * @dev Checks if a permissions node is empty, which means that it
   * has no children and no explicit permissions set.
   */
  function isEmpty (PermissionsNode storage node) private view returns (bool)
  {
    return node.keys.length == 0
        && node.fullAccess.keys.length == 0
        && node.fallbackAccess.keys.length == 0;
  }

  /**
   * @dev Removes all "empty" tree nodes along the specified branch to clean
   * up storage.  If a node has no children and both permission maps are
   * empty (no keys with associations), then it will be removed.  This has
   * "almost" no effect on permissions, with the exception being that it may
   * grant back permissions to addresses with fallback access.
   *
   * This method is used recursively, and considers only the tail of the
   * path array starting at the given "start" index.
   */
  function removeEmptyNodes (PermissionsNode storage node,
                             string[] memory path, uint start) private
  {
    /* If the current node does not exist or is at the leaf level,
       there is nothing to do.  Deleting of empty nodes is done one
       level up (from the call on its parent node), so that the parent's
       book-keeping data can be updated as well.  */
    if (node.indexAndOne == 0 || start == path.length)
      return;
    assert (start < path.length);

    /* Process the child node first, so descendant nodes further down
       are cleared now (if any).  */
    PermissionsNode storage child = node.children[path[start]];
    removeEmptyNodes (child, path, start + 1);

    /* If the child node is empty, remove it.  */
    if (isEmpty (child))
      {
        uint oldIndex = child.indexAndOne;
        delete node.children[path[start]];

        if (oldIndex > 0)
          {
            if (oldIndex < node.keys.length)
              {
                string memory last = node.keys[node.keys.length - 1];
                node.keys[oldIndex - 1] = last;

                PermissionsNode storage lastNode = node.children[last];
                assert (lastNode.indexAndOne > 0);
                lastNode.indexAndOne = oldIndex;
              }

            node.keys.pop ();
          }
      }
  }

  /**
   * @dev Revokes a particular permission at the given tree level
   * and in the fallback or full-access map (based on the flag).
   *
   * This method does not perform any checks, so callers need to ensure
   * that it is actually ok to revoke that entry (e.g. the message sender
   * has the required authorisation).
   *
   * If this leads to completely "empty" tree nodes, they will be removed
   * and cleaned up as well.  Note that this may, in special situations, lead
   * to expanded permissions of an address with fallback access.
   */
  function revoke (PermissionsNode storage root, string[] memory path,
                   address operator, bool fallbackOnly) internal
  {
    PermissionsNode storage node = retrieveNode (root, path, false);
    removeEntry (fallbackOnly ? node.fallbackAccess : node.fullAccess,
                 operator);

    removeEmptyNodes (root, path, 0);
  }

  /* ************************************************************************ */

  /**
   * @dev Clears an entire PermissionsMap completely.
   */
  function clear (PermissionsMap storage map) private
  {
    for (uint i = 0; i < map.keys.length; ++i)
      delete map.forAddress[map.keys[i]];
    delete map.keys;
  }

  /**
   * @dev Revokes all permissions in the entire hierarchy starting at
   * the given node.  If deleteNode is set, then the node itself
   * will be removed (i.e. also the indexAndOne it has as marker).  If not,
   * then it will remain.
   */
  function revokeTree (PermissionsNode storage node, bool deleteNode) private
  {
    clear (node.fullAccess);
    clear (node.fallbackAccess);

    for (uint i = 0; i < node.keys.length; ++i)
      revokeTree (node.children[node.keys[i]], true);
    delete node.keys;

    if (deleteNode)
      delete node.indexAndOne;
  }

  /**
   * @dev Revokes all permissions for a node at a given path.
   */
  function revokeTree (PermissionsNode storage root, string[] memory path)
      internal
  {
    revokeTree (retrieveNode (root, path, false), false);
  }

  /* ************************************************************************ */

}
