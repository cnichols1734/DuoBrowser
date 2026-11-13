# Filter data attribution

EasyList and EasyPrivacy: **The EasyList authors (https://easylist.to/)**.
These source lists are distributed under **Creative Commons Attribution-ShareAlike
3.0 Unported**, selecting that alternative from the upstream dual license:
https://easylist.to/pages/licence.html . Full text: `CC-BY-SA-3.0.txt`.

EasyList Cookie List: **The EasyList authors and Fanboy**. Its own header specifies
**Creative Commons Attribution 3.0 Unported**. Full text: `CC-BY-3.0.txt`.
Source: https://secure.fanboy.co.nz/fanboy-cookiemonster.txt .

The bundled `.txt` lists retain their rules and headers; trailing whitespace is
removed from comment lines only. `metadata.json` records upstream and bundled
SHA-256 digests, this transformation, and retrieval date (seconds since 2001-01-01 UTC).
DuoBrowser converts a supported subset into declarative WebKit JSON: unsupported
syntax is omitted, domains/resource conditions are preserved or the entire rule
is skipped, exceptions are ordered after blocking rules, and large lists are
split with their relevant exceptions repeated. The converted EasyList/EasyPrivacy
data remains CC BY-SA 3.0. Cookie-list transformations remain attributed under CC
BY 3.0. These licenses apply to filter data, not the independent MIT application
code. No AdGuard converter code or other third-party runtime library is included.

Original source locations:
- https://easylist.to/easylist/easylist.txt
- https://easylist.to/easylist/easyprivacy.txt
- https://secure.fanboy.co.nz/fanboy-cookiemonster.txt

Sources and converter are publicly available with this repository. The filter
credits and full licenses are also accessible offline in the app under Filter
Lists → Filter Credits & Licenses. No affiliation or endorsement is implied.
