// SPDX-License-Identifier: MIT
// Copyright (C) 2025 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import { stringArray } from "./TestUtils.sol";
import "../src/JsonSubObject.sol";

import { Test } from "forge-std/Test.sol";

contract JsonSubObjectTest is Test
{

  /**
   * @dev Helper function that exposes atPath from the library as an external
   * function, which properly works with vm.expectRevert.
   */
  function atPath (string[] memory path, string memory val)
      external pure returns (string memory)
  {
    return JsonSubObject.atPath (path, val);
  }

  function test_handlesPath () public view
  {
    string memory subObject
        = "{\"foo\": \"bar\","
          " \"array\": [1, 2, 3],"
          " \"sub\": {\"ok\": true},"
          " \"null\": null}";

    vm.assertEq (this.atPath (stringArray (), subObject), subObject);

    vm.assertEq (this.atPath (stringArray ("x"), subObject),
                 string.concat ("{\"x\":", subObject, "}"));

    vm.assertEq (this.atPath (stringArray ("x", "y", "z"), subObject),
                 string.concat ("{\"x\":{\"y\":{\"z\":", subObject, "}}}"));
  }

  function test_validSubObjects () public view
  {
    string[] memory tests = new string[] (3);
    tests[0] = "{}";
    tests[1] = "{\"abc\": [1, 2, 3]}";
    tests[2] = "{\"foo\": \"}}}\\\"}}}\"}";

    for (uint i = 0; i < tests.length; ++i)
      vm.assertEq (this.atPath (stringArray (), tests[i]), tests[i]);
  }

  function test_invalidSubObjects () public
  {
    string[] memory tests = new string[] (11);

    /* Only JSON objects without leading or trailing whitespace are allowed
       for simplicity.  */
    tests[0] = "";
    tests[1] = " {}";
    tests[2] = "{} ";
    tests[3] = "123";
    tests[4] = "null";
    tests[5] = "[1, 2, 3]";

    /* Unmatched strings or brackets.  */
    tests[6] = "{\"foo}";
    tests[7] = "{\"foo\":{\"bar\":42}";
    tests[8] = "{\"foo\":{\"bar\":42}}}";

    /* This would be an actual injection attack.  */
    tests[9] = "{},\"other\":{\"injection\":true}";

    /* We detect ends of string literals correctly, even if backslashes
       are there to confuse us.  */
    tests[10] = "{\"abc\": \"string\\\\\"},\"other\":{\"injection\":true}";

    for (uint i = 0; i < tests.length; ++i)
      {
        vm.expectRevert ("possible JSON injection attempt");
        this.atPath (stringArray ("x"), tests[i]);
      }
  }

  function test_validPathKeys () public view
  {
    string[] memory validKeys = new string[] (4);
    validKeys[0] = "";
    validKeys[1] = "abc";
    validKeys[2] = unicode"äöü";
    validKeys[3] = "a-b-c 1 2 3 & 4";

    for (uint i = 0; i < validKeys.length; ++i)
      vm.assertEq (this.atPath (stringArray (validKeys[i]), "{}"),
                   string.concat ("{\"", validKeys[i], "\":{}}"));
  }

  function test_invalidPathKeys () public
  {
    string[] memory invalidKeys = new string[] (2);
    invalidKeys[0] = "possible\"injection";
    invalidKeys[1] = "escaping closing quote\\";

    for (uint i = 0; i < invalidKeys.length; ++i)
      {
        vm.expectRevert ("invalid path key");
        this.atPath (stringArray ("x", invalidKeys[i], "y"), "{}");
      }
  }

}
