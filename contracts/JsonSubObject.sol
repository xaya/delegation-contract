// SPDX-License-Identifier: MIT
// Copyright (C) 2022 Autonomous Worlds Ltd

pragma solidity ^0.8.13;

/**
 * @dev A Solidity library that implements building of JSON moves
 * where a user-supplied "sub object" is placed at some specified
 * path (e.g. user-supplied move for a particular game ID in Xaya).
 * This includes validation required to ensure that users cannot
 * "inject" fake JSON strings to manipulate and break out of the
 * specified path.
 */
library JsonSubObject
{

  /**
   * @dev Checks if a string is a "safe" JSON object serialisation.  This means
   * that the string is either a valid and complete JSON object, or that it
   * will certainly produce invalid JSON if concatenated with other JSON
   * strings and placed at the position for some JSON value.
   * For simplicity, this method does not accept leading or trailing
   * whitespace around the outer-most {} of the object.
   *
   * This method is at the heart of the safe sub-object construction.
   * It ensures that the user-provided string cannot lead to an "injection"
   * of JSON syntax that breaks out of the intended path it is placed at,
   * either because it is a valid and proper JSON object, or because it will
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

       The main thing we need to do for this is ensure that the outermost
       {} brackets of the JSON object are properly matched; the value should
       begin with { and end with }, and while processing the string, there
       should always be at least one level of {} brackets open.  Other brackets
       (i.e. []) are not relevant, because if they are mismatched, it will
       ensure the final JSON value is certainly invalid.

       In addition to that, we need to track string literals well enough to
       ignore any brackets inside of them.  For this, we need to keep track
       of whether or not a string literal is open, and also properly handle
       \" (do not close it) and \\ (if followed by ", it closes the string).

       Any other validation or processing is not necessary.  We also don't have
       to deal with UTF-8 characters in any case (those can be part of
       string literals), as those are cannot interfere with the basic
       control syntax in JSON (which is ASCII).  Any invalid UTF-8 will just
       result in invalid UTF-8 (and thus, and invalid value) in the end.  */

    bytes memory data = bytes (str);

    /* The very first character should be the opening {.  */
    if (data.length < 1 || data[0] != '{')
      return false;

    int depth = 1;
    bool openString = false;
    bool afterBackslash = false;

    for (uint i = 1; i < data.length; ++i)
      {
        /* While we have more to process, we should never leave the
           outermost layer of brackets.  This is checked when processing
           the closing bracket, but just double-check it here.  */
        assert (depth > 0);

        /* Check if we are inside a string literal.  If we are, we need to
           look for its closing ", and handle backslash escapes.  */
        if (openString)
          {
            if (afterBackslash)
              {
                /* We don't have to care whatever comes after an escape.
                   The thing that matters is that it is not a closing ".  */
                afterBackslash = false;
                continue;
              }

            if (data[i] == '"')
              openString = false;
            else if (data[i] == '\\')
              afterBackslash = true;

            continue;
          }

        /* We are not inside a string literal, so track brackets and
           watch for opening of strings.  */

        assert (!afterBackslash);

        if (data[i] == '"')
          openString = true;
        else if (data[i] == '{')
          ++depth;
        else if (data[i] == '}')
          {
            --depth;
            assert (depth >= 0);
            /* We should always have a depth larger than zero, except for
               the very last character which will be the final closing } that
               leads to depth zero.  */
            if (depth == 0 && i + 1 != data.length)
              return false;
          }
      }

    /* At the end, all brackets should indeed be closed.  */
    return (depth == 0);
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
   * sub-object is present at the given "path" within the full object.
   * Elements of "path" are supposed to be simple field names that don't
   * need escaping inside a JSON string literal.
   *
   * If the user-supplied string is indeed a valid JSON object, then this
   * method returns valid JSON as well (for the full object).  If the
   * subobject string is not a valid JSON object, then this method may
   * either revert or return a string that is invalid JSON (but it is guaranteed
   * to not return successfully a string that is valid).
   */
  function atPath (string[] memory path, string memory subObject)
      internal pure returns (string memory res)
  {
    require (isSafe (subObject), "possible JSON injection attempt");

    res = subObject;
    for (int i = int (path.length) - 1; i >= 0; --i)
      {
        string memory key = path[uint (i)];
        require (isSafeKey (key), "invalid path key");
        res = string (abi.encodePacked ("{\"", key, "\":", res, "}"));
      }
  }

}
