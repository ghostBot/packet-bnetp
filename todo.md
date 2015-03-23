## done ##
### most important ###
  * ~~array of any basic type (actually, uint32[5](5.md) may be enough)~~
    * ~~display it as one value (e.g. passhash uint32 [5](5.md) - 40 char string)~~
  * ~~conditions (if..)~~
  * ~~string-dword (swap dword and output as string)~~
  * ~~supress raw values output on custom types (time, dwordstr)~~
  * ~~iterator from 0 to x (cdkey/gamelist)~~
    * Wireshark needs a patch to correctly highlight each element in the hexdump.
      * [Still not included in 1.2.3](https://bugs.wireshark.org/bugzilla/show_bug.cgi?id=3994)
      * [Alien](http://alien.luaforge.net/): Lua's FFI. The patch may not be needed after all :) (at the cost of an extra dependency)
      * It will be available in Wireshark versions 1.4.x. (currently a release candidate)
  * ~~iteration until empty string (S>0x0b getchannellist)~~
    * don't display last empty entry?

### less important ###
  * ~~ip (network byte order, opposite to intel). For some reason lua's built-in ipv4 uses inter order (lol?)~~
  * ~~windows (?) file time, used in sid\_getfiletime~~
    * can be converted to posixtime
    * $unixtime = $wintime/1E7 - 11644473600
  * ~~unips file time~~
  * ~~exe version decoder (like ip, but in intel order)~~
  * ~~enclosed iterators (for s>0x26 readuserdata)~~
  * ~~make clienttag a type (so it's no need to write possible values every time)?~~ - valuemaps for strdw
  * ~~bitmap decoder (user flag)~~
  * ~~sid\_checkad: extension: string[4](4.md)~~
  * ~~"decode as" if both ports not 6112 (e.g. using proxy): can't define who is server and who client~~
    * ~~At least, add config section at the beginning of the file~~
    * ~~Add lite mode configuration.~~
  * ~~Add heading with instructions~~
  * Prevent Wireshark from crashing by properly validating the packets' descriptions and give useful feedback in case of errors.
    * Bug of lua interpreter / wireshark lua interface / wireshark itself?
      * Crashed, if hash and usual forms were mixed in function call.
    * Crashed 1.2.3 and [latest pre-release win32-1.2.7pre1-31873](http://www.wireshark.org/download/prerelease/wireshark-win32-1.2.7pre1-31873.exe). I think, we need to report bug. 1.2.6 [didn't even worked on 2000](https://bugs.wireshark.org/bugzilla/show_bug.cgi?id=4176)
  * ~~Mixed parameter form in function call, like in python~~
    * Done. Does it work?
      * Yes, it does.
  * Investigate GeoIP.
    * It only shows something in IPv4 Tree.
  * ~~SID\_CHATEVENT event id and SID\_WARCRAFTGENERAL subcommand id as filter?~~
    * ~~Authomatically append "bnetp." to filter name~~