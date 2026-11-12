### Internal
- `.gitignore` keeps Apple signing keys and provisioning profiles (`.p8`,
  `.p12`, `.cer`, `.mobileprovision`, `.provisionprofile`, `AuthKey_*`) out of git. None has ever
  been committed; the rule makes sure a file dropped into the project folder
  stays out.
