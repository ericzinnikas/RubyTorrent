#Project Notes / Specs

##References
####(Info on bencoding, metainfo files, trackers, and peer protocols)

- [Official BitTorrent Spec][http://bittorrent.org/beps/bep_0003.html]
- [BitTorrent Spec Wiki][https://wiki.theory.org/BitTorrentSpecification]

##Design Choices
- **Module** that implements all low-level procotols, etc.
- **Driver** (high-level, uses our module) for actual client implementation
- **Tester** runs driver, along with official BitTorrent client (benchmarking, etc.)
