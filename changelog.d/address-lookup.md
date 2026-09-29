### Fixed
- **An address the map can't place is no longer saved silently.** Adding a client (by hand or from a scanned business card), or changing a client's address, when the address can't be put on the map now asks: save without a map pin (or, for a client who already has one, keep it), or edit the address. If the map couldn't be reached (no signal, say), it says so and offers Try Again.
  - Adding a client used to save them with no pin, which leaves them off route maps, with no drive times and no job-site alerts, and nothing said so.
  - Changing the address used to keep the old address's pin without asking, so a client who had moved stayed at their old house on every map and route.
  - Edit Client now saves a new address only once it's been looked up, and can't be left or changed while that runs.
- **A client with no pin can be given one.** Their page has "Set Pin on the Map". The map opens where you are, or around your other clients, and the pin can be confirmed once you've zoomed in to the house. A pin set by hand keeps the address as typed, even one typed just before. "Adjust Pin" used to be hidden for these clients, so the missing pin couldn't be fixed.
- **Adjust Pin saves only when the pin moved.** Opening it looked the pin's address up again, and Confirm wrote that back, often reformatted or a neighbour's number, over the client's address.
- **A picked address suggestion keeps its pin.** The address field threw it away as soon as it filled in, so saving looked the address up again, and the suggestions came back.
