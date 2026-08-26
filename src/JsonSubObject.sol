// SPDX-License-Identifier: MIT
// Copyright (C) 2022-2026 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @dev A Solidity library that implements building of JSON moves
 * where a user-supplied "sub value" is placed at some specified
 * path (e.g. user-supplied move for a particular game ID in Xaya).
 * This includes validation required to ensure that users cannot
 * "inject" fake JSON strings to manipulate and break out of the
 * specified path.
 */
library JsonSubObject
{

  /**
   * @dev Tries to read a complete string literal from the given input string,
   * starting at position start.  Returns true if a (potentially valid) string
   * literal was found starting at this position (opening quote), and ending
   * (character after the closing quote) at the returned end.  Returns false
   * if no valid string literal was found or it was not closed before the
   * end of the string.
   */
  function readStringLiteral (bytes memory str, uint start)
      private pure returns (bool, uint)
  {
    uint p = start;
    if (p >= str.length || str[p] != '"')
      return (false, p);

    bool afterBackslash = false;
    for (++p; p < str.length; ++p)
      {
        /* Whatever comes after a backslash doesn't matter.  It cannot close
           the string literal.  */
        if (afterBackslash)
          {
            afterBackslash = false;
            continue;
          }
      
        if (str[p] == '"')
          return (true, p + 1);

        if (str[p] == '\\')
          afterBackslash = true;
      }

    /* We reached the end of the string without finding a closing quote.  */
    return (false, p);
  }

  /**
   * @dev Tries to read a complete integer literal from the given input string,
   * starting at position start.  Returns true if a potentially valid literal
   * was found, and false otherwise.  Returns end pointing to the character
   * after the last character consumed.
   */
  function readIntLiteral (bytes memory str, uint start)
      private pure returns (bool, uint)
  {
    uint p = start;
    if (p >= str.length)
      return (false, p);

    /* If the string is just "0", that is valid.  Otherwise it may not
       start with a zero, and we follow the parsing path below.  */
    if (str[p] == '0')
      return (true, p + 1);

    /* Consume a potential initial "-" sign.  */
    if (str[p] == '-')
      ++p;

    /* We expect a non-zero digit as the first one.  */
    if (p >= str.length || str[p] < '1' || str[p] > '9')
      return (false, p);

    /* Now zero or more digits (0-9) may follow.  */
    for (++p; p < str.length; ++p)
      if (str[p] < '0' || str[p] > '9')
        break;

    return (true, p);
  }

  /**
   * @dev Tries to read a complete expression enclosed by a pair of {}
   * (for objects) or [] (for arrays).  Returns true if an expression
   * with matching brackets of this type can be found, and returns false if
   * there is something wrong (does not start with the opening bracket, or
   * brackets mismatched).  Returns end pointing to the character after
   * the last character consumed.
   *
   * This only validates that the read expression has balanced (potentially
   * nested) brackets of the given type, and it ignores everything inside
   * a string literal.
   */
  function readBracketExpression (bytes memory str, uint start,
                                  bytes1 open, bytes1 close)
      private pure returns (bool, uint)
  {
    uint p = start;

    /* The very first character should be the opening bracket.  */
    if (p >= str.length || str[p] != open)
      return (false, p);

    int depth = 1;
    for (++p; p < str.length; ++p)
      {
        /* While we have more to process, we should never leave the
           outermost layer of brackets.  This is checked when processing
           the closing bracket, but just double-check it here.  */
        assert (depth > 0);

        /* If a string literal comes, just skip it.  */
        (bool isString, uint afterString) = readStringLiteral (str, p);
        if (isString)
          {
            /* The continue will run ++p, and we want to continue processing
               in the next iteration at afterString directly.  */
            p = afterString - 1;
            continue;
          }

        /* We already know there is no *valid* string literal.  If there still
           is an opening quote, it means this is invalid.  */
        if (str[p] == '"')
          return (false, p);

        if (str[p] == open)
          ++depth;
        else if (str[p] == close)
          {
            --depth;
            assert (depth >= 0);
            if (depth == 0)
              return (true, p + 1);
          }
      }

    /* We should have closed all brackets within the data available, so if
       we reach here, the value is not valid.  */
    assert (depth > 0);
    return (false, p);
  }

  /**
   * @dev Checks if a string is a "safe" JSON object serialisation.  This means
   * that the string is either a valid and complete JSON value (where we
   * support a subset of full JSON), or that it will certainly produce invalid
   * JSON if concatenated with other JSON strings and placed at the position
   * for some JSON value.  For simplicity, this method does not accept leading
   * or trailing whitespace around the expression.
   *
   * This method is at the heart of the safe sub-object construction.
   * It ensures that the user-provided string cannot lead to an "injection"
   * of JSON syntax that breaks out of the intended path it is placed at,
   * either because it is a valid and proper JSON value, or because it will
   * at least produce invalid JSON in the end which leads to invalid moves.
   * By allowing the latter, we can simplify the processing necessary in
   * Solidity to a minimum.
   */
  function isSafe (string memory str) private pure returns (bool)
  {
    /* Essentially, what this method needs to detect and reject are
       strings like:

         null},"other game":{...

       If such a string would be put as sub-object into a particular place
       by adding something like

         {"g":{"some game":

       at the front and }} at the end, it could lead to attacks actually
       injecting move data for another game into what is, in the end,
       a fully valid JSON move.

       Note that we don't have to deal with UTF-8 characters in any case
       (those can be part of string literals), as those are cannot interfere
       with the basic control syntax in JSON (which is ASCII).  Any invalid
       UTF-8 will just result in invalid UTF-8 (and thus, and invalid value)
       in the end.  */

    bytes memory data = bytes (str);

    /* Check for valid boolean or null literals.  */
    if (Strings.equal (str, "true") || Strings.equal (str, "false")
          || Strings.equal (str, "null"))
      return true;

    /* Check to see if we have a string, integer, object or array literal
       using the respective helper functions.  Note that in any case, it should
       always consume the entire input.  */

    bool found;
    uint end;
    
    (found, end) = readStringLiteral (data, 0);
    if (found)
      return end == data.length;

    (found, end) = readIntLiteral (data, 0);
    if (found)
      return end == data.length;

    (found, end) = readBracketExpression (data, 0, '{', '}');
    if (found)
      return end == data.length;

    (found, end) = readBracketExpression (data, 0, '[', ']');
    if (found)
      return end == data.length;

    /* No match to a provably-safe type of value was found.  */
    return false;
  }

  /**
   * @dev Checks if a string is safe as "string literal".  This means that
   * if quotes are added around it but nothing else is done, it is sure to
   * be a valid string literal.
   */
  function isSafeKey (string memory str) private pure returns (bool)
  {
    /* This method is used to check that the keys in a path are safe,
       in a quick and simple way.  We simply check that the string does
       not contain any \ or " characters, which is enough to guarantee
       that enclosing in quotes will safely yield a valid string literal.

       This prevents some strings from ever being possible to create,
       but since those are meant for object keys anyway, the main use will
       be stuff like all-lower-case ASCII names.  */

    bytes memory data = bytes (str);

    for (uint i = 0; i < data.length; ++i)
      if (data[i] == '"' || data[i] == '\\')
        return false;

    return true;
  }

  /**
   * @dev Builds up a string representing a JSON object where the user-supplied
   * value is present at the given "path" within the full object.
   * Elements of "path" are supposed to be simple field names that don't
   * need escaping inside a JSON string literal.
   *
   * If the user-supplied string is indeed a valid, supported JSON value, then
   * this method returns valid JSON as well (for the full object).  If the
   * value string is not a valid JSON value, then this method may
   * either revert or return a string that is invalid JSON (but it is guaranteed
   * to not return successfully a string that is valid).
   */
  function atPath (string[] memory path, string memory value)
      internal pure returns (string memory res)
  {
    require (isSafe (value), "possible JSON injection attempt");

    res = value;
    for (int i = int (path.length) - 1; i >= 0; --i)
      {
        // forge-lint: disable-next-line(unsafe-typecast)
        string memory key = path[uint (i)];
        require (isSafeKey (key), "invalid path key");
        res = string (abi.encodePacked ("{\"", key, "\":", res, "}"));
      }
  }

}
