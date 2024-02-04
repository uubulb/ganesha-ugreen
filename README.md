#### A simple bash script helps you automatically install & configure nfs-ganesha on your UGreen NAS.

#### How to run:
```
curl -L https://mirror.ghproxy.com/https://raw.githubusercontent.com/uubulb/ganesha-ugreen/main/ganesha.sh -o ganesha.sh && bash ./ganesha.sh
```
#### TODO List:
- [ ] Add comments.
- [ ] English version of the script.
- [ ] Generate real absolute path on startup by integrating the feature into service script.
- [ ] Ability to modify path, client, etc.

This script is designed to download prebuilt nfs-ganesha binaries to your system, with build flags specified in the release note. If you have any security concerns, it is recommended to use your own build instead.