#RubyTorrent

Started off as a class project, hopefully we'll get some development going forward over the next few months.

###Description
* Implement a BitTorrent client
  + Should be able to interoperate with commercial/open-source clients
- Demonstrate our implementation downloads files within **10%** of the speed of an official client (with a comprable number of peers)
- Devise an experiment to demonstrate our client is *fast enough* and *stable* in comparison to the official BitTorrent client

###Wishlist:
* DHT tracker
* PropShare[1], compare performance to official client
* Under-reporting, compare performance to official client
* A protocol to detect under-reporting

###Notes
* See [here](NOTES.md)

###Usage
* See [here](USAGE.md)

###References
[1] Dave Levin, Katrina LaCurts, Neil Spring, and Bobby Bhattacharjee. Bittorrent is an auction: Analyzing and improving bittorrent's incentives. SIGCOMM Comput. Commun. Rev., 38(4):243–254, August 2008.
