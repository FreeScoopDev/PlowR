### Internal
- CI: a hung test fails after 2 minutes, naming the test, instead of running the whole job into its 45-minute limit, and the test log is kept when a run fails or is cancelled. #190's first run hung, GitHub cancelled the job, and no log was saved to say which test it was.
