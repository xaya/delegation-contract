// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

const truffleAssert = require ("truffle-assertions");

const JsonSubObject = artifacts.require ("JsonSubObjectTestHelper");

contract ("JsonSubObject", accounts => {
  let so;
  before (async () => {
    so = await JsonSubObject.new ();
  });

  it ("handles the path correctly", async () => {
    const subObject = {
      "foo": "bar",
      "array": [1, 2, 3],
      "sub": {"ok": true},
      "null": null,
    };
    const str = JSON.stringify (subObject);

    assert.deepEqual (JSON.parse (await so.atPath ([], str)), subObject);
    assert.deepEqual (JSON.parse (await so.atPath (["x"], str)),
                      {"x": subObject});
    assert.deepEqual (JSON.parse (await so.atPath (["x", "y", "z"], str)),
                      {"x": {"y": {"z": subObject}}});
  });

  it ("accepts valid sub-objects", async () => {
    const validStrings = [
      "{}",
      "{\"abc\": [1, 2, 3]}",
      "{\"foo\": \"}}}\\\"}}}\"}",
    ];

    for (const str of validStrings)
      assert.deepEqual (JSON.parse (await so.atPath ([], str)),
                        JSON.parse (str));
  });

  it ("rejects invalid sub-objects", async () => {
    const invalidStrings = [
      /* Only JSON objects without leading or trailing whitespace are allowed
         for simplicity.  */
      "",
      " {}",
      "{} ",
      "123",
      "null",
      "[1, 2, 3]",

      /* Unmatched strings or brackets.  */
      "{\"foo}",
      "{\"foo\":{\"bar\":42}",
      "{\"foo\":{\"bar\":42}}}",

      /* This would be an actual injection attack.  */
      "{},\"other\":{\"injection\":true}",

      /* We detect ends of string literals correctly, even if backslashes
         are there to confuse us.  */
      "{\"abc\": \"string\\\\\"},\"other\":{\"injection\":true}",
    ];

    for (const str of invalidStrings)
      await truffleAssert.reverts (so.atPath (["x"], str), "injection");
  });

  it ("accepts valid path keys", async () => {
    const validKeys = [
      "",
      "abc",
      "äöü",
      "a-b-c 1 2 3 & 4",
    ];

    for (const str of validKeys)
      {
        let expected = {};
        expected[str] = {};
        assert.deepEqual (JSON.parse (await so.atPath ([str], "{}")), expected);
      }
  });

  it ("rejects invalid path keys", async () => {
    const invalidKeys = [
      "possible\"injection",
      "escaping closing quote\\",
    ];

    for (const str of invalidKeys)
      await truffleAssert.reverts (so.atPath (["x", str, "y"], "{}"),
                                   "invalid path key");
  });

});
