// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");
const { time } = require ("@openzeppelin/test-helpers");

const NamePermissions = artifacts.require ("NamePermissions");

const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

contract ("NamePermissions", acc => {
  let np;
  beforeEach (async () => {
    np = await NamePermissions.new ();
  });

  /**
   * Grants a given permission.  This sends the transaction from the
   * desired owner, so that it will always go through.  This helper method
   * can be used in tests where not the granting itself is under test, but
   * the permissions are needed for other tests.
   */
  const grant = async (tokenId, owner, path, operator,
                       expiration, fallback) => {
    await np.grant (tokenId, owner, path, operator, expiration, fallback,
                    {from: owner});
  };

  it ("allows to read the state", async () => {
    await grant (1, acc[0], ["g", "id"], acc[3], 100, true);
    await grant (1, acc[0], ["g", "id"], acc[1], 42, false);
    await grant (1, acc[0], ["g", "id"], acc[2], 50, false);
    await grant (1, acc[0], ["g"], acc[0], 200, false);
    await grant (2, acc[1], [], acc[2], 100, true);

    assert.isTrue (await np.permissionExists (1, acc[0], ["g"]));
    assert.isFalse (await np.permissionExists (1, acc[0], ["g", "id", "bar"]));
    assert.isFalse (await np.permissionExists (2, acc[0], []));
    assert.isTrue (await np.permissionExists (2, acc[1], []));

    assert.isTrue (await np.permissionExists (2, acc[1], [], acc[2], true));
    assert.isFalse (await np.permissionExists (2, acc[1], ["g"], acc[2], true));
    assert.isFalse (await np.permissionExists (2, acc[1], [], acc[3], true));
    assert.isFalse (await np.permissionExists (2, acc[1], [], acc[2], false));
    assert.isFalse (await np.permissionExists (2, acc[0], [], acc[0], false));

    assert.equal (
        await np.getExpiration (1, acc[0], ["g", "id"], acc[1], false),
        42);
    assert.equal (
        await np.getExpiration (1, acc[0], ["g", "id"], acc[1], true),
        0);
    assert.equal (await np.getExpiration (1, acc[0], ["g", "id"], acc[3], true),
                  100);
    assert.equal (await np.getExpiration (2, acc[1], ["g"], acc[2], true), 0);
    assert.equal (await np.getExpiration (2, acc[0], [], acc[0], true), 0);
    assert.equal (await np.getExpiration (3, acc[1], [], acc[0], false), 0);

    let keys = await np.getDefinedKeys (1, acc[0], ["g", "id"]);
    assert.deepEqual (keys[0], []);
    assert.deepEqual (keys[1], [acc[1], acc[2]]);
    assert.deepEqual (keys[2], [acc[3]]);
    keys = await np.getDefinedKeys (1, acc[0], ["g"]);
    assert.deepEqual (keys[0], ["id"]);
    assert.deepEqual (keys[1], [acc[0]]);
    assert.deepEqual (keys[2], []);
    keys = await np.getDefinedKeys (3, acc[0], ["g"]);
    assert.deepEqual (keys[0], []);
    assert.deepEqual (keys[1], []);
    assert.deepEqual (keys[2], []);
  });

  it ("checks access correctly", async () => {
    await grant (1, acc[0], ["g", "id"], acc[1], 10, true);
    await grant (2, acc[1], [], acc[2], 10, false);

    assert.isTrue (await np.hasAccess (1, acc[0], ["g", "id"], acc[0], 1000));
    assert.isFalse (await np.hasAccess (1, acc[0], ["g", "id"], acc[1], 10));
    assert.isTrue (await np.hasAccess (1, acc[0], ["g", "id", "bar"],
                                       acc[1], 10));

    assert.isTrue (await np.hasAccess (2, acc[1], ["foo"], acc[1], 1000));
    assert.isTrue (await np.hasAccess (2, acc[1], ["foo"], acc[2], 10));
    assert.isFalse (await np.hasAccess (2, acc[1], ["foo"], acc[2], 11));

    assert.isTrue (await np.hasAccess (2, acc[0], ["foo"], acc[0], 1000));
    assert.isFalse (await np.hasAccess (2, acc[0], ["foo"], acc[2], 1));
    assert.isTrue (await np.hasAccess (3, acc[0], ["foo"], acc[0], 1000));
    assert.isFalse (await np.hasAccess (3, acc[0], ["foo"], acc[2], 1));
  });

  it ("handles granting of permissions", async () => {
    /* We can start to seed permissions by the owner themselves, but later
       on, also people with permissions (including fallback permissions)
       can grant more.  */
    await np.grant (1, acc[0], [], acc[1], 1000, true, {from: acc[0]});
    await np.grant (1, acc[0], ["foo"], acc[2], 100, false, {from: acc[1]});
    await np.grant (1, acc[0], ["bar"], acc[2], 100, false, {from: acc[1]});

    await truffleAssert.reverts (
        np.grant (2, acc[0], [], acc[1], 10, false, {from: acc[1]}),
        "the sender has no access");
    await truffleAssert.reverts (
        np.grant (1, acc[0], ["foo"], acc[3], 10, false, {from: acc[1]}),
        "the sender has no access");
    await truffleAssert.reverts (
        np.grant (1, acc[0], ["foo"], acc[3], 101, false, {from: acc[2]}),
        "the sender has no access");
  });

  it ("handles revoking of permissions", async () => {
    await grant (1, acc[0], ["g"], acc[1], 100, true);
    await grant (1, acc[0], ["g", "id"], acc[2], maxUint256, false);
    await grant (1, acc[0], ["g", "id"], acc[3], maxUint256, true);
    await grant (1, acc[0], ["g", "id"], acc[4], 10, false);

    /* Someone with only fallback permission can never revoke.  */
    await truffleAssert.reverts (
        np.revoke (1, acc[0], ["g", "id"], acc[2], false, {from: acc[3]}),
        "the sender has no access");
    /* Someone with limited-in-time permission cannot revoke.  */
    await truffleAssert.reverts (
        np.revoke (1, acc[0], ["g", "id"], acc[2], false, {from: acc[4]}),
        "the sender has no access");

    /* Some with unlimited access can revoke.  */
    await np.revoke (1, acc[0], ["g", "id"], acc[4], false, {from: acc[2]});
    /* The owner themselves can always revoke.  */
    await np.revoke (1, acc[0], ["g", "id"], acc[2], false, {from: acc[0]});
    /* The operator address can revoke its own permissions.  */
    await np.revoke (1, acc[0], ["g", "id"], acc[3], true, {from: acc[3]});
    await np.revoke (1, acc[0], ["g"], acc[1], true, {from: acc[1]});

    assert.isFalse (await np.permissionExists (1, acc[0], []));

    /* The operator and owner can revoke permissions even if they don't
       exist (i.e. it succeeds but won't have any effect).  */
    await np.revoke (1, acc[0], [], acc[1], false, {from: acc[0]});
    await np.revoke (1, acc[0], [], acc[1], false, {from: acc[1]});
  });

  it ("handles tree resets correctly", async () => {
    await grant (1, acc[0], ["g"], acc[1], maxUint256, false);
    await grant (1, acc[0], ["g"], acc[2], 10, false);
    await grant (1, acc[0], ["g"], acc[2], maxUint256, true);
    await grant (1, acc[0], ["g", "id"], acc[3], 10, false);
    await grant (1, acc[0], ["g", "id"], acc[3], maxUint256, true);

    /* Someone with fallback access or time-limited access cannot reset
       a subtree (as that would give them full access).  */
    await truffleAssert.reverts (
        np.resetTree (1, acc[0], ["g", "id"], {from: acc[2]}),
        "the sender has no access");

    /* Resetting a non-existing node (but with access permissions) should
       work fine.  It does nothing for the owner, and actually creates a new
       permission entry for a non-owner.  */
    await np.resetTree (1, acc[0], ["g", "foo"], {from: acc[0]});
    assert.isFalse (await np.permissionExists (1, acc[0], ["g", "foo"]));
    await np.resetTree (1, acc[0], ["g", "foo"], {from: acc[1]});
    assert.isTrue (await np.permissionExists (1, acc[0], ["g", "foo"]));

    /* Test resetting an existing node, which should clean out the subtree.
       The sender will keep access.  */
    await np.resetTree (1, acc[0], ["g"], {from: acc[1]});
    assert.isTrue (await np.permissionExists (1, acc[0], ["g"]));
    assert.isFalse (await np.permissionExists (1, acc[0], ["g", "foo"]));
    assert.isFalse (await np.permissionExists (1, acc[0], ["g", "id"]));
    assert.isTrue (await np.hasAccess (1, acc[0], ["g"], acc[1], maxUint256));

    /* If the owner themselves resets, it will remove empty nodes as well.  */
    await np.resetTree (1, acc[0], [], {from: acc[0]});
    assert.isFalse (await np.permissionExists (1, acc[0], []));
    assert.isTrue (await np.hasAccess (1, acc[0], [], acc[0], maxUint256));
  });

  it ("allows expiring of permissions", async () => {
    await time.advanceBlock ();
    const start = (await time.latest ()).toNumber ();

    await grant (1, acc[0], [], acc[1], start + 100, false);
    await grant (1, acc[0], [], acc[2], start + 100, true);
    await grant (1, acc[0], ["g"], acc[2], start + 100, true);
    await grant (1, acc[0], ["g"], acc[3], start + 200, false);

    /* Nothing is expired yet.  */
    await np.expireTree (1, acc[0], [], {from: acc[4]});
    assert.isTrue (await np.permissionExists (1, acc[0], ["g"], acc[2], true));
    assert.isTrue (await np.permissionExists (1, acc[0], ["g"], acc[3], false));

    /* Some entries are expired, but also only those will be evaluated that
       we expire explicitly.  */
    await time.increase (150);
    await np.expireTree (1, acc[0], ["g"], {from: acc[4]});
    assert.isFalse (await np.permissionExists (1, acc[0], ["g"], acc[2], true));
    assert.isTrue (await np.permissionExists (1, acc[0], ["g"], acc[3], false));

    /* Expire the entire "g" tree.  Note that this can cause fallback
       permissions to "increase" in scope.  */
    assert.isFalse (await np.hasAccess (1, acc[0], ["g"], acc[2], 1));
    await time.increase (100);
    await np.expireTree (1, acc[0], ["g"], {from: acc[4]});
    assert.isFalse (await np.permissionExists (1, acc[0], ["g"]));
    assert.isTrue (await np.hasAccess (1, acc[0], ["g"], acc[2], 1));

    /* Expire the entire tree.  */
    await np.expireTree (1, acc[0], []);
    assert.isFalse (await np.permissionExists (1, acc[0], []));
    assert.isFalse (await np.hasAccess (1, acc[0], ["g"], acc[2], 1));
  });

});
