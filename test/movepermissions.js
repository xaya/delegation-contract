// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const MovePermissions = artifacts.require ("MovePermissionsTestHelper");

const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

contract ("MovePermissions", acc => {
  let mp;
  beforeEach (async () => {
    mp = await MovePermissions.new ();
  });

  const expectKeys = async (path, children, access, fallback) => {
    const actual = await mp.getKeys (path);
    assert.deepEqual (actual[0], children);
    assert.deepEqual (actual[1], access);
    assert.deepEqual (actual[2], fallback);
  };

  const expectTimestamps = async (path, operator, access, fallback) => {
    const actual = await mp.getTimestamps (path, operator);
    assert.equal (actual[0], access);
    assert.equal (actual[1], fallback);
  };

  it ("grants permissions correctly", async () => {
    await mp.grant ([], acc[0], maxUint256, true);
    await mp.grant (["g", "id"], acc[1], maxUint256, false);
    await mp.grant (["g", "id"], acc[2], 100, false);
    await mp.grant (["g", "id"], acc[2], 100, false);
    await mp.grant (["g", "id"], acc[2], 101, false);

    await truffleAssert.reverts (mp.grant ([], acc[0], 0, false),
                                 "zero expiration");
    await truffleAssert.reverts (mp.grant (["g", "id"], acc[2], 90, false),
                                 "has longer validity than new grant");

    assert.isFalse (await mp.isEmpty ([]));
    assert.isFalse (await mp.isEmpty (["g"]));
    assert.isFalse (await mp.isEmpty (["g", "id"]));
    assert.isTrue (await mp.isEmpty (["g", "id", "foo"]));
    assert.isTrue (await mp.isEmpty (["g", "tn"]));

    await expectKeys ([], ["g"], [], [acc[0]]);
    await expectKeys (["g"], ["id"], [], []);
    await expectKeys (["g", "id"], [], [acc[1], acc[2]], []);
    await expectKeys (["g", "id", "foo"], [], [], []);

    await expectTimestamps ([], acc[0], 0, maxUint256);
    await expectTimestamps ([], acc[1], 0, 0);
    await expectTimestamps (["g", "id"], acc[1], maxUint256, 0);
    await expectTimestamps (["g", "id"], acc[2], 101, 0);
  });

  it ("checks permissions correctly", async () => {
    await mp.grant (["g"], acc[0], maxUint256, true);
    await mp.grant (["g", "id"], acc[1], 200, false);

    await truffleAssert.reverts (mp.check ([], acc[0], 0), "must not be zero");

    assert.isFalse (await mp.check ([], acc[0], 1));
    assert.isFalse (await mp.check (["g"], acc[0], 1));
    assert.isTrue (await mp.check (["g", "foo"], acc[0], maxUint256));

    assert.isFalse (await mp.check ([], acc[1], 1));
    assert.isFalse (await mp.check (["x"], acc[1], 1));
    assert.isTrue (await mp.check (["g", "id"], acc[1], 200));
    assert.isFalse (await mp.check (["g", "id"], acc[1], 201));
    assert.isFalse (await mp.check (["g", "id"], acc[1], maxUint256));
    assert.isTrue (await mp.check (["g", "id", "foo"], acc[1], 200));
  });

  it ("revokes permissions correctly", async () => {
    await mp.grant (["g", "id"], acc[0], maxUint256, true);
    await mp.grant (["g", "id", "first"], acc[1], maxUint256, false);
    await mp.grant (["g", "id", "foo", "bar"], acc[1], 1, false);
    await mp.grant (["g", "id", "foo", "bar"], acc[2], 2, false);
    await mp.grant (["g", "id", "foo", "bar"], acc[3], 3, false);
    await mp.grant (["g", "id", "foo", "bar"], acc[1], 4, true);

    /* Revoking a non-existing permission is fine and just doesn't do
       anything.  Same for a non-existing node path.  */
    await mp.revoke (["g", "id", "foo", "bar"], acc[4], true);
    await mp.revoke (["g", "id", "foo", "bar", "baz"], acc[1], false);

    /* Revoke permissions and remove a child node from within the list.  */
    assert.isTrue (await mp.check (["g", "id", "first"], acc[1], 1));
    assert.isFalse (await mp.isEmpty (["g", "id", "first"]));
    await expectKeys (["g", "id"], ["first", "foo"], [], [acc[0]]);
    await mp.revoke (["g", "id", "first"], acc[1], false);
    assert.isFalse (await mp.check (["g", "id", "first"], acc[1], 1));
    assert.isTrue (await mp.isEmpty (["g", "id", "first"]));
    await expectKeys (["g", "id"], ["foo"], [], [acc[0]]);

    /* Revoke the permissions again, making sure to remove them both
       from the "end" of the list and from the middle.  */
    await mp.revoke (["g", "id", "foo", "bar"], acc[3], false);
    await expectKeys (["g", "id", "foo", "bar"], [],
                      [acc[1], acc[2]], [acc[1]]);
    await expectTimestamps (["g", "id", "foo", "bar"], acc[1], 1, 4);
    await mp.revoke (["g", "id", "foo", "bar"], acc[1], true);
    await expectTimestamps (["g", "id", "foo", "bar"], acc[1], 1, 0);
    await expectKeys (["g", "id", "foo", "bar"], [], [acc[1], acc[2]], []);
    await mp.revoke (["g", "id", "foo", "bar"], acc[1], false);
    await expectKeys (["g", "id", "foo", "bar"], [], [acc[2]], []);
    await expectTimestamps (["g", "id", "foo", "bar"], acc[2], 2, 0);
    assert.isFalse (await mp.isEmpty (["g", "id", "foo", "bar"]));

    /* In the current set up, the fallback permission at g/id does
       not apply too foo.  */
    assert.isFalse (await mp.check (["g", "id", "foo"], acc[0], 1));

    /* Revoke the last permission at the node, and it will be removed
       together with all other empty parent nodes.  */
    await mp.revoke (["g", "id", "foo", "bar"], acc[2], false);
    await expectKeys (["g", "id", "foo", "bar"], [], [], []);
    await expectKeys (["g", "id"], [], [], [acc[0]]);
    assert.isTrue (await mp.isEmpty (["g", "id", "foo", "bar"]));
    assert.isTrue (await mp.isEmpty (["g", "id", "foo"]));
    assert.isFalse (await mp.isEmpty (["g", "id"]));

    /* Now the fallback access will be enabled again.  */
    assert.isTrue (await mp.check (["g", "id", "foo"], acc[0], 1));

    /* Remove the last permission, cleaning out the entire tree.  */
    await mp.revoke (["g", "id"], acc[0], true);
    assert.isTrue (await mp.isEmpty (["g", "id"]));
    assert.isTrue (await mp.isEmpty (["g"]));
    /* The root node will not be considered completely empty according to
       our function definition in the test helper (since it exists), but
       it will have no contents.  */
    assert.isFalse (await mp.isEmpty ([]));
    await expectKeys ([], [], [], []);
  });

  it ("can revoke entire permission trees", async () => {
    await mp.grant (["g", "id"], acc[0], 1, true);
    await mp.grant (["g", "id", "foo"], acc[1], 2, true);
    await mp.grant (["g", "id", "foo", "bar"], acc[2], 3, false);
    await mp.grant (["g", "id", "foo", "bar"], acc[2], 4, true);
    await mp.grant (["g", "id", "foo", "bar"], acc[3], 5, true);
    await mp.grant (["g", "id", "foo", "baz"], acc[2], 6, false);

    assert.isTrue (await mp.check (["g", "id", "foo", "bar"], acc[2], 1));
    await mp.revokeTree (["g", "id", "foo"]);
    assert.isFalse (await mp.check (["g", "id", "foo", "bar"], acc[2], 1));
    assert.isFalse (await mp.isEmpty (["g", "id", "foo"]));
    assert.isTrue (await mp.isEmpty (["g", "id", "foo", "bar"]));
    await expectKeys (["g", "id"], ["foo"], [], [acc[0]]);
    await expectKeys (["g", "id", "foo"], [], [], []);

    assert.isTrue (await mp.check (["g", "id", "x"], acc[0], 1));
    await mp.revokeTree ([]);
    /* Revoking a non-existing tree is fine, too (and has no effect).  */
    await mp.revokeTree (["a", "b", "c"]);

    assert.isFalse (await mp.check (["g", "id", "x"], acc[0], 1));
    assert.isFalse (await mp.isEmpty ([]));
    assert.isTrue (await mp.isEmpty (["g"]));
    assert.isTrue (await mp.isEmpty (["g", "id"]));
    assert.isTrue (await mp.isEmpty (["g", "id", "foo"]));
    assert.isTrue (await mp.isEmpty (["g", "id", "foo", "bar"]));
    await expectKeys ([], [], [], []);
    await expectKeys (["g", "id"], [], [], []);
  });

});
