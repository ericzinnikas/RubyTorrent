#Project Notes / Specs

##References
####Bencoding, metainfo files, trackers, and peer protocol details

- [Official BitTorrent Spec](http://bittorrent.org/beps/bep_0003.html)
- [BitTorrent Spec Wiki](https://wiki.theory.org/BitTorrentSpecification)

##Design Choices
- **Module** that implements all low-level procotols, etc.
- **Driver** (high-level, uses our module) for actual client implementation
- **Tester** runs driver, along with official BitTorrent client (benchmarking, etc.)
