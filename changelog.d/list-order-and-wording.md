### Fixed
- Two services with the same place in the catalog now come out in the same order on every screen and device (contract and request-link service lists, client and property forms, proposals, Add Visit, the catalog itself). Each list sorted by place alone, so a tie, such as two services added on two devices before syncing, could come out differently from screen to screen. They all use the one catalog order, which breaks a tie by ID.
- A job's name on the client timeline, a contract's days ("Every Tuesday and Friday") and a job's services in the Service Log history are joined with English words on a phone set to another language. They used the device's joining word ("Mow et Trim") inside English copy.

### Internal
- The exit-offer source test also pins that the offer reads its button afresh (`memoized: false`).
